# -*- coding: utf-8; -*-
#
# scraping nikkei.com for Kindlizer
#

require 'nokogiri'
require 'open-uri'
require 'tmpdir'
require 'pathname'

module Kindlizer
	module Generator
		class NikkeiFree
			TOP = 'http://www.nikkei.com'

			def initialize( tmpdir )
				@current_dir = tmpdir

				@src_dir = @current_dir + '/src'
				Dir::mkdir( @src_dir )

				@dst_dir = @current_dir + '/dst'
				Dir::mkdir( @dst_dir )
				FileUtils.cp( "./resource/nikkei.jpg", @dst_dir )
				FileUtils.cp( "./resource/nikkei.css", @dst_dir )
			end

			def generate
				toc = []
				top = Nokogiri( open( TOP, 'r:utf-8', &:read ) )
				
				#
				# scraping top news
				#
				toc_top = ['TOP NEWS']
				
				%w(first second_alone third fourth).each do |category|
					(top / "div.nx-top_news_#{category} h3 a").each do |a|
						toc_top << [canonical( a.text.strip ), a.attr( 'href' )]
					end
				end
				toc << toc_top
				
				#
				# scraping all categories
				#
				(top / 'div.cmnc-genre').each do |genre|
					toc_cat = []
					(genre / 'h4.cmnc-genre_title a').each do |cat|
						next if /local/ =~ cat.attr( 'href' )
						toc_cat << cat.text
						(genre / 'li a').each do |article|
							toc_cat << [canonical( article.text ), article.attr( 'href' )]
						end
					end
					toc << toc_cat
				end
				
				begin
					generate_contents( toc )
					yield "#{@dst_dir}/nikkei-free.opf"
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
					<link rel="stylesheet" href="nikkei.css" type="text/css" media="all"></link>
				</head>
				<body>
					<h1>#{title}</h1>
				HTML
			end
			
			def get_html_item( uri, sub = nil )
				uri.sub!( %r|^http://www.nikkei.com|, '' )
				aid = uri2aid( uri )
				html = nil
				if File::exist?( "#{@src_dir}/#{aid}#{sub}.html" ) # loading cache
					html = Nokogiri( open( "#{@src_dir}/#{aid}#{sub}.html", 'r:utf-8', &:read ) )
				else
					begin
						#puts "getting html #{aid}#{sub}"
						retry_loop( 5 ) do
							html = Nokogiri( open( "#{TOP}#{uri}", 'r:utf-8', &:read ) )
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
					(div / 'div.cmn-photo_style2 img').each do |image_tag|
						image_url = image_tag.attr( 'src' )
						next if /^http/ =~ image_url
						image_file = File::basename( image_url )
						#puts "   getting image #{image_file}"
						begin
							image = open( "#{TOP}#{image_url.sub /PN/, 'PB'}", &:read )
							open( "#{@dst_dir}/#{image_file}", 'w' ){|fp| fp.write image}
							result << %Q|\t<p><img src="#{image_file}"></p>|
						rescue
							$stderr.puts "FAIL TO DOWNLOAD IMAGE: #{image_url}"
						end
					end
					(div / 'p').each do |text|
						next unless (text / 'a.cmnc-continue').empty?
						(text / 'span.JSID_urlData').remove
						para = canonical text.text.strip.sub( /^　/, '' )
						result << "\t<p>#{para}</p>" unless para.empty?
					end
					(div / 'table').each do |table|
						result << table.to_html
					end
				end
				result
			end
			
			def html_item( item, uri )
				aid = uri2aid( uri )
				return '' unless aid
				html = get_html_item( uri )
			
				open( "#{@dst_dir}/#{aid}.html", 'w:utf-8' ) do |f|
					f.puts canonical( html_header( (html / 'h4.cmn-article_title, h2.cmn-article_title')[0].text.strip ) )
					f.puts scrape_html_item( html )
					(html / 'div.cmn-article_nation ul li a').map {|link|
						link.attr( 'href' )
					}.sort.uniq.each_with_index do |link,index|
						f.puts scrape_html_item( get_html_item( link, index + 2 ) )
					end
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
				<docTitle><text>日経電子版 (#{Time::now.strftime '%Y-%m-%d %H:%M'})</text></docTitle>
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
							<dc:Title>日経電子版 (#{Time::now.strftime '%Y-%m-%d %H:%M'})</dc:Title>
							<dc:Language>en-US</dc:Language>
							<dc:Creator>日本経済新聞社</dc:Creator>
							<dc:Description>日経電子版、#{Time::now.strftime '%Y-%m-%d %H:%M'}生成</dc:Description>
							<dc:Date>#{Time::now.strftime( '%d/%m/%Y' )}</dc:Date>
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
				uri.scan( /g=([^;$]+)/ ).flatten[0]
			end
			
			def generate_contents( toc )
				open( "#{@dst_dir}/toc.html", 'w:utf-8' ) do |html|
				open( "#{@dst_dir}/toc.ncx", 'w:utf-8' ) do |ncx|
				open( "#{@dst_dir}/nikkei-free.opf", 'w:utf-8' ) do |opf|
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
								html.puts html_item( article[0], article[1] )
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
