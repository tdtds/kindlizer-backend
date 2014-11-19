# -*- coding: utf-8; -*-
#
# scraping jp.wsj.com for Kindlizer
#

require 'mechanize'
require 'nokogiri'
require 'open-uri'
require 'tmpdir'
require 'pathname'
require 'json'

module Kindlizer
	module Generator
		class WsjPaid
			TOP = 'http://jp.wsj.com'
			LOGIN = "https://id.wsj.com/access/pages/wsj/jp/login_standalone.html"

			def initialize( tmpdir )
				begin
					require 'pit'
					login = Pit::get( 'wsj', :require => {
						'user' => 'your ID of WSJ.',
						'pass' => 'your Password of WSJ.',
					} )
					@wsj_id = login['user']
					@wsj_pw = login['pass']
				rescue LoadError # no pit library, using environment variables
					@wsj_id = ENV['WSJ_ID']
					@wsj_pw = ENV['WSJ_PW']
				end

				@current_dir = tmpdir

				@src_dir = @current_dir + '/src'
				Dir::mkdir( @src_dir ) if(!File.exist?( @src_dir ))

				@dst_dir = @current_dir + '/dst'
				Dir::mkdir( @dst_dir ) if(!File.exist?( @dst_dir ))
				FileUtils.cp( "./resource/wsj.jpg", @dst_dir )
				FileUtils.cp( "./resource/wsj.css", @dst_dir )
			end

			def generate(opts)
				@now = opts[:now]
				@now_str = @now.strftime '%Y-%m-%d %H:%M'
				@title = "WSJ日本版"
				@lang = "ja-JP"

				agent = Mechanize::new
				agent.set_proxy( *ENV['HTTP_PROXY'].split( /:/ ) ) if ENV['HTTP_PROXY']

				toc = []
				toc_cat = []

				agent.get(LOGIN)

				form = agent.page.forms.first
				form.action = ('https://id.wsj.com/auth/submitlogin.json')
				form['username'] = @wsj_id
				form['password'] = @wsj_pw
				agent.page.forms.first.submit

				response = JSON.parse(agent.page.body)
				agent.get( response["url"] )

				agent.get( TOP + "/home-page?_wsjregion=asia,jp&_homepage=/home/jp")

				#
				# scraping top news
				#
				toc_top = ['TOP NEWS']
				(agent.page / "div.whatsNews ul.newsItem h2 a").each do |a|
					if(a.attr('href') =~ /^http:\/\/jp.wsj.com\/article\//)
						toc_top << [canonical( a.text.strip ), a.attr( 'href' )]
					end
				end
				toc << toc_top

				#
				# scraping all categories
				#
				first = true
				(agent.page.root / 'div.wsjMainNav li').each do |li|
					if(first)
						first = false
						next
					end

					a = (li / 'a').first
					toc_cat = []
					toc_cat << canonical( a.text.strip )
					begin
						retry_loop( 5 ) do
							agent.get(a.attr( 'href' ))
							sleep 1
						end
					rescue
						$stderr.puts "cannot get #{uri}."
						raise
					end

					count = 0
					(agent.page / "div.leadModule" ).remove
					newsLinks = (agent.page / "div.headlineSummary ul.newsItem h2 a" )
					newsLinks.each do |a|
						if(a.attr('href') =~ /^http:\/\/jp.wsj.com\/article\//)
							toc_cat << [canonical( a.text.strip ), a.attr( 'href' )]
							count += 1
							break if(count >= 10)
						end
					end
					toc << toc_cat
				end

				begin
					generate_contents( toc, agent )
					yield "#{@dst_dir}/wsj-paid.opf"
				end
			end

		private

			def canonical( str )
				str.gsub( /\uFF5E/, "\u301C" ) # for WAVE DASH problem
			end

			def retry_loop( times )
				count = 0
				begin
					yield
				rescue
					count += 1
					if count >= times
						raise
					else
						$stderr.puts $!
						$stderr.puts "#{count} retry."
						retry
					end
				end
			end

			def html_header( title )
				<<-HTML.gsub( /^\t/, '' )
				<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
				<html>
				<head>
					<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></meta>
					<title>#{title}</title>
					<link rel="stylesheet" href="wsj.css" type="text/css" media="all"></link>
				</head>
				<body>
					<h1>#{title}</h1>
				HTML
			end

			def get_html_item( agent, uri, sub = nil )
				aid = uri2aid( uri )
				html = nil
				if File::exist?( "#{@src_dir}/#{aid}#{sub}.html" ) # loading cache
					html = Nokogiri( open( "#{@src_dir}/#{aid}#{sub}.html", 'r:utf-8', &:read ) )
				else
					begin
						#puts "getting html #{aid}#{sub}"
						retry_loop( 5 ) do
							agent.get( uri )
							html = agent.page.root
							sleep 1
						end
					rescue
						$stderr.puts "cannot get #{uri}."
						raise
					end
					open( "#{@src_dir}/#{aid}#{sub}.html", 'w:utf-8' ) do |f|
						f.write( html.to_html )
					end
				end
				html
			end

			def scrape_html_item( html )
				contents = (html / 'div#article_story_body')

				if(contents.size == 0)
					contents = (html / 'div#slideContainer')
					if(contents.size > 0)
						(contents / 'div.dSlideViewer').before((contents / 'div.dSlideViewer li.firstSlide').inner_html)
						(contents / 'div.dSlideViewer, h2.header, ul.nav-inline').remove
					end
				else
					signature = (contents / 'ul.socialByline')
					if(signature.size > 0)
						signature[0].before(signature.inner_text)
						signature.remove
					end
					(contents / 'div.insettipBox , div.insetButton').remove
					(contents / 'div.insetZoomTargetBox a').remove
					(contents / 'div.legacyInset div.embedType-interactive').each {|d| d.parent.remove}
				end

				(contents / 'img').each do |image_tag|
					image_url = image_tag.attr( 'src' )
					image_file = File::basename( image_url )
					if(File.exist?("#{@dst_dir}/#{image_file}"))
						image_tag.set_attribute("src", image_file)
						next
					end
					#puts "   getting image #{image_file}"
					begin
						image = open( image_url, &:read )
						open( "#{@dst_dir}/#{image_file}", 'w' ){|fp| fp.write image}
						image_tag.set_attribute("src", image_file)
					rescue
						$stderr.puts "FAIL TO DOWNLOAD IMAGE: #{image_url}"
					end
				end

				contents.inner_html
			end

			def html_item( item, uri, agent )
				aid = uri2aid( uri )
				return '' unless aid
				html = get_html_item( agent, uri )

				open( "#{@dst_dir}/#{aid}.html", 'w:utf-8' ) do |f|
					title_tag = (html / 'meta[@property="og:title"]')
					title = title_tag.size > 0 ? title_tag[0].attr("content").strip : item
					f.puts canonical( html_header( title ) )

					f.puts scrape_html_item(html)
					f.puts html_footer
				end

				%Q|\t\t<li><a href="#{aid}.html">#{item}</a></li>|
			end

			def html_footer
				<<-HTML.gsub( /^\t/, '' )
				</body>
				</html>
				HTML
			end

			def ncx_header
				<<-XML.gsub( /^\t/, '' )
				<?xml version="1.0" encoding="UTF-8"?>
				<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
				<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
				<docTitle><text>#{@title} (#{@now_str})</text></docTitle>
				<navMap>
					<navPoint id="toc" playOrder="0"><navLabel><text>Table of Contents</text></navLabel><content src="toc.html" /></navPoint>
				XML
			end

			def ncx_item( item, uri, index )
				aid = uri2aid( uri )
				aid ? %Q|\t\t<navPoint id="#{aid}" playOrder="#{index}"><navLabel><text>#{item}</text></navLabel><content src="#{aid}.html" /></navPoint>| : ''
			end

			def ncx_footer
				<<-XML.gsub( /^\t/, '' )
				</navMap>
				</ncx>
				XML
			end

			def opf_header
				<<-XML.gsub( /^\t/, '' )
				<?xml version="1.0" encoding="utf-8"?>
				<package unique-identifier="uid">
					<metadata>
						<dc-metadata xmlns:dc="http://purl.org/metadata/dublin_core" xmlns:oebpackage="http://openebook.org/namespaces/oeb-package/1.0/">
							<dc:Title>#{@title} (#{@now_str})</dc:Title>
							<dc:Language>#{@lang}</dc:Language>
							<dc:Creator>The Wall Street Journal Online</dc:Creator>
							<dc:Description>#{@title}、#{@now_str}生成</dc:Description>
							<dc:Date>#{@now.strftime( '%d/%m/%Y' )}</dc:Date>
						</dc-metadata>
						<x-metadata>
							<output encoding="utf-8" content-type="text/x-oeb1-document"></output>
							<EmbeddedCover>wsj.jpg</EmbeddedCover>
						</x-metadata>
					</metadata>
					<manifest>
						<item id="toc" media-type="application/x-dtbncx+xml" href="toc.ncx"></item>
						<item id="style" media-type="text/css" href="wsj.css"></item>
						<item id="index" media-type="text/html" href="toc.html"></item>
				XML
			end

			def opf_item( uri )
				aid = uri2aid( uri )
				aid ? %Q|\t\t<item id="#{aid}" media-type="text/html" href="#{aid}.html"></item>| : ''
			end

			def opf_footer( aids )
				r = <<-XML.gsub( /^\t/, '' )
				</manifest>
				<spine toc="toc">
				XML
				aids.each do |aid|
					r << %Q|\t<itemref idref="#{aid}" />\n|
				end
				r << <<-XML.gsub( /^\t/, '' )
					<itemref idref="index" />
				</spine>
				<tours></tours>
				<guide>
				  <reference type="toc" title="Table of Contents" href="toc.html"></reference>
				  <reference type="start" title="Top Story" href="#{aids[0]}.html"></reference>
				</guide>
				</package>
				XML
				r
			end

			def uri2aid( uri )
				uri.scan( %r|/article/([^/]*).html| ).flatten[0]
			end

			def generate_contents( toc, agent )
				open( "#{@dst_dir}/toc.html", 'w:utf-8' ) do |html|
				open( "#{@dst_dir}/toc.ncx", 'w:utf-8' ) do |ncx|
				open( "#{@dst_dir}/wsj-paid.opf", 'w:utf-8' ) do |opf|
					first = true
					toc_index = 0
					aids = []
					ncx.puts ncx_header
					opf.puts opf_header
					toc.each do |category|
						category.each do |article|
							if article.class == String
								html.puts first ?
									html_header( 'Table of Contents' ) :
									"\t</ul>\n\t<mbp:pagebreak />"
								html.puts "\t<h2>#{article}</h2>"
								html.puts "\t<ul>"
								first = false
							else
								html.puts html_item( article[0], article[1], agent )
								ncx.puts ncx_item( article[0], article[1], toc_index += 1 )
								unless aids.index( uri2aid( article[1] ) )
									opf.puts opf_item( article[1] )
									aids << uri2aid( article[1] ) if uri2aid( article[1] )
								end
							end
						end
					end
					html.puts "\t</ul>"
					html.puts html_footer
					ncx.puts ncx_footer
					opf.puts opf_footer( aids )
				end
				end
				end
			end
		end
	end
end
