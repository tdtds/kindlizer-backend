# -*- coding: utf-8; -*-
#
# scraping nikkei.com (for paid user) for Kindlizer
#

require 'mechanize'
require 'nokogiri'
require 'open-uri'
require 'tmpdir'
require 'pathname'

module Kindlizer
	module Generator
		class NikkeiPaid
			class IllegalPage < StandardError; end

			TOP = 'https://www.nikkei.com'
			LOGIN = "#{TOP}/etc/accounts/login?dps=3&amp;pageflag=top&amp;url=http%3A%2F%2Fwww.nikkei.com%2F"

			def initialize( tmpdir )
				@nikkei_id, @nikkei_pw = auth
				@current_dir = tmpdir

				@src_dir = @current_dir + '/src'
				Dir::mkdir( @src_dir )

				@dst_dir = @current_dir + '/dst'
				Dir::mkdir( @dst_dir )
				FileUtils.cp( "./resource/nikkei.jpg", @dst_dir )
				FileUtils.cp( "./resource/nikkei.css", @dst_dir )
			end

			def generate(opts)
				@now = opts[:now]
				@now_str = @now.strftime '%Y-%m-%d %H:%M'

				agent = Mechanize::new
				agent.set_proxy( *ENV['HTTP_PROXY'].split( /:/ ) ) if ENV['HTTP_PROXY']

				toc = []
				if @nikkei_id and @nikkei_pw
					agent.get('https://regist.nikkei.com/ds/etc/accounts/logout')
					agent.get( LOGIN )
					agent.page.form_with( :name => 'autoPostForm' ).submit
					agent.page.form_with( :name => 'LA7010Form01' ) do |form|
						form['LA7010Form01:LA7010Email'] = @nikkei_id
						form['LA7010Form01:LA7010Password'] = @nikkei_pw
						form.click_button
					end
					agent.page.forms.first.submit
				else
					agent.get( TOP )
				end

				#
				# scraping top news
				#
				toc_top = ['TOP NEWS']
				%w(first second third fourth).each do |category|
					(agent.page / "div.nx-top_news_#{category} h3 a").each do |a|
						uri = a.attr('href')
						next if Kindlizer::Backend::DupChecker.dup?(uri)
						toc_top << [canonical( a.text.strip ), uri]
					end
				end
				toc << toc_top

				#
				# scraping all categories
				#
				(agent.page / 'div.cmnc-genre').each do |genre|
					toc_cat = []
					(genre / 'h4.cmnc-genre_title a.cmnc-title_text').each do |cat|
						next if /local/ =~ cat.attr( 'href' )
						toc_cat << cat.text
						(genre / 'li a').each do |article|
							uri = article.attr('href')
							next if Kindlizer::Backend::DupChecker.dup?(uri)
							toc_cat << [canonical( article.text ), uri]
						end
					end
					toc << toc_cat
				end

				begin
					generate_contents( toc, agent )
					yield "#{@dst_dir}/#{basename}.opf"
				end

				if @nikkei_id and @nikkei_pw
					agent.get('https://regist.nikkei.com/ds/etc/accounts/logout')
				end
			end

		private

			def auth
				id = ENV['NIKKEI_ID']
				pw = ENV['NIKKEI_PW']
				if !id || !pw
					begin
						require 'pit'
						login = Pit::get( 'nikkei', :require => {
							'user' => 'your ID of Nikkei.',
							'pass' => 'your Password of Nikkei.',
						} )
						id = login['user']
						pw = login['pass']
					rescue LoadError # no pit library, using environment variables
						id, pw = nil, nil
					end
				end
				return id, pw
			end

			def basename
				self.class.to_s.sub(/.*:/, '').gsub(/([A-Z])/, '-\\1').sub(/^-/, '').downcase
			end

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
				<<~HTML
					<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
					<html>
					<head>
						<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></meta>
						<title>#{title}</title>
						<link rel="stylesheet" href="nikkei.css" type="text/css" media="all"></link>
					</head>
					<body>
						<h1>#{title}</h1>
				HTML
			end

			def get_html_item( agent, uri, sub = nil )
				uri.sub!( %r|^https://www.nikkei.com|, '' )
				aid = uri2aid( uri )
				html = nil
				if File::exist?( "#{@src_dir}/#{aid}#{sub}.html" ) # loading cache
					html = Nokogiri( open( "#{@src_dir}/#{aid}#{sub}.html", 'r:utf-8', &:read ) )
				else
					begin
						#puts "getting html #{aid}#{sub}"
						retry_loop( 5 ) do
							agent.get( "#{TOP}#{uri}" )
							html = agent.page.root
							sleep 1
						end
					rescue
						$stderr.puts "cannot get #{TOP}#{uri}."
						raise
					end
					open( "#{@src_dir}/#{aid}#{sub}.html", 'w:utf-8' ) do |f|
						f.write( html.to_html )
					end
				end
				html
			end

			def scrape_html_item( html )
				result = ''
				(html / 'div.cmn-article_text').each do |div|
					div.children.each do |e|
					#div.css('div.cmn-photo_style2 img', 'p', 'table').each do |e|
						case e.name
						when 'p'
							next unless (e / 'a.cmnc-continue').empty?
							(e / 'span.JSID_urlData').remove
							para = canonical e.text.strip.sub( /^　/, '' )
							result << "\t<p>#{para}</p>" unless para.empty?
						when 'table'
							result << e.to_html
						when 'div'
							e.css('img').each do |img|
								image_url = img['src']
								next if /^http/ =~ image_url # skip images in other server
								next if /^\/\// =~ image_url # skip assets
								image_file = File::basename( image_url )
								begin
									image = open( "#{TOP}#{image_url.sub /PN/, 'PB'}", &:read )
									open( "#{@dst_dir}/#{image_file}", 'w' ){|fp| fp.write image}
									result << %Q|\t<div>|
									result << %Q|\t\t<img src="#{image_file}">|
									result << %Q|\t\t<p>[#{e.text}]</p>| unless e.text.strip.empty?
									result << %Q|\t</div>|
								rescue
									p $!
									$stderr.puts "FAIL TO DOWNLOAD IMAGE: #{image_url}"
								end
							end
						end
					end
				end
				result
			end

			def html_item( item, uri, agent )
				aid = uri2aid( uri )
				return '' unless aid
				html = get_html_item( agent, uri )
				out_file = "#{@dst_dir}/#{aid}.html"

				begin
					open( out_file, 'w:utf-8' ) do |f|
						f.puts canonical( html_header( (html / 'h1.cmn-article_title, h4.cmn-article_title, h2.cmn-article_title')[0].text.strip ) )
						f.puts scrape_html_item( html )
						(html / 'div.cmn-article_nation ul li a').map {|link|
							link.attr( 'href' )
						}.sort.uniq.each_with_index do |link,index|
							f.puts scrape_html_item( get_html_item( agent, link, index + 2 ) )
						end
						f.puts html_footer
					end

					%Q|\t\t<li><a href="#{aid}.html">#{item}</a></li>|
				rescue NoMethodError
					$stderr.puts "page parsing faild. #{aid}"
					$stderr.puts $!
					File.delete out_file
					raise IllegalPage.new
				end
			end

			def html_footer
				<<~HTML
					</body>
					</html>
				HTML
			end

			def ncx_header
				<<~XML
					<?xml version="1.0" encoding="UTF-8"?>
					<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
					<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
					<docTitle><text>日経電子版 (#{@now_str})</text></docTitle>
					<navMap>
						<navPoint id="toc" playOrder="0"><navLabel><text>Table of Contents</text></navLabel><content src="toc.html" /></navPoint>
				XML
			end

			def ncx_item( item, uri, index )
				aid = uri2aid( uri )
				aid ? %Q|\t\t<navPoint id="#{aid}" playOrder="#{index}"><navLabel><text>#{item}</text></navLabel><content src="#{aid}.html" /></navPoint>| : ''
			end

			def ncx_footer
				<<~XML
					</navMap>
					</ncx>
				XML
			end

			def opf_header
				<<~XML
					<?xml version="1.0" encoding="utf-8"?>
					<package unique-identifier="uid">
						<metadata>
							<dc-metadata xmlns:dc="http://purl.org/metadata/dublin_core" xmlns:oebpackage="http://openebook.org/namespaces/oeb-package/1.0/">
								<dc:Title>日経電子版 (#{@now_str})</dc:Title>
								<dc:Language>ja-JP</dc:Language>
								<dc:Creator>日本経済新聞社</dc:Creator>
								<dc:Description>日経電子版、#{@now_str}生成</dc:Description>
								<dc:Date>#{@now.strftime( '%d/%m/%Y' )}</dc:Date>
							</dc-metadata>
							<x-metadata>
								<output encoding="utf-8" content-type="text/x-oeb1-document"></output>
								<EmbeddedCover>nikkei.jpg</EmbeddedCover>
							</x-metadata>
						</metadata>
						<manifest>
							<item id="toc" media-type="application/x-dtbncx+xml" href="toc.ncx"></item>
							<item id="style" media-type="text/css" href="nikkei.css"></item>
							<item id="index" media-type="text/html" href="toc.html"></item>
				XML
			end

			def opf_item( uri )
				aid = uri2aid( uri )
				aid ? %Q|\t\t<item id="#{aid}" media-type="text/html" href="#{aid}.html"></item>| : ''
			end

			def opf_footer( aids )
				items = aids.map{|aid| %Q|\t<itemref idref="#{aid}" />|}
				<<~XML
					</manifest>
					<spine toc="toc">
						#{items.join("\n")}
						<itemref idref="index" />
					</spine>
					<tours></tours>
					<guide>
					  <reference type="toc" title="Table of Contents" href="toc.html"></reference>
					  <reference type="start" title="Top Story" href="#{aids[0]}.html"></reference>
					</guide>
					</package>
				XML
			end

			def uri2aid( uri )
				uri.scan( %r|/article/([^/]*)/| ).flatten[0]
			end

			def generate_contents( toc, agent )
				open( "#{@dst_dir}/toc.html", 'w:utf-8' ) do |html|
				open( "#{@dst_dir}/toc.ncx", 'w:utf-8' ) do |ncx|
				open( "#{@dst_dir}/#{basename}.opf", 'w:utf-8' ) do |opf|
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
								begin
									html.puts html_item( article[0], article[1], agent )
									ncx.puts ncx_item( article[0], article[1], toc_index += 1 )
									unless aids.index( uri2aid( article[1] ) )
										opf.puts opf_item( article[1] )
										aids << uri2aid( article[1] ) if uri2aid( article[1] )
									end
								rescue IllegalPage
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
