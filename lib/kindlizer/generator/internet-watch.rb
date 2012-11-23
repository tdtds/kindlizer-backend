# -*- coding: utf-8; -*-
#
# scraping internet.watch.impress.co.jp for Kindlizer
#

require 'nokogiri'
require 'open-uri'
require 'uri'
require 'ostruct'
require 'tmpdir'
require 'pathname'
require 'fileutils'

module Kindlizer
	module Generator
		class InternetWatch
			TOP = 'http://internet.watch.impress.co.jp'
			
			def initialize( tmpdir )
				@current_dir = tmpdir

				@src_dir = @current_dir + '/src'
				Dir::mkdir( @src_dir )

				@dst_dir = @current_dir + '/dst'
				Dir::mkdir( @dst_dir )
				FileUtils.cp( "./resource/internet-watch.jpg", @dst_dir )
				FileUtils.cp( "./resource/internet-watch.css", @dst_dir )
			end

			def generate( now )
				items = []
				
				rdf_file = "#{TOP}/cda/rss/internet.rdf"
				rdf = retry_loop( 5 ) do
					Nokogiri( open( rdf_file, 'r:utf-8', &:read ) )
				end
				(rdf / 'item' ).each do |item|
					uri = URI( item.attr( 'about' ) )
					next unless /internet\.watch\.impress\.co\.jp/ =~ uri.host
					uri.query = nil # remove query of 'from rss'
				
					title = (item / 'title').text
				
					items <<  OpenStruct::new( :uri => uri, :title => title )
				end
				
				now_str = now.strftime( '%Y-%m-%d %H:%M' )
				
				#
				# generating articles in html
				#
				items.each do |item|
					begin
						article = get_article( item.uri )
						open( "#{@dst_dir}/#{item_id item.uri}.html", 'w' ) do |f|
							f.puts html_header( item.title )
							contents = (article / 'div.mainContents')
							(contents / 'img').each do |img|
								org = img.attr( 'src' )
								begin
									img_file = retry_loop( 5 ) do
										open( "#{TOP}#{org}", &:read )
									end
									cache = "#{org.gsub( /\//, '_' ).sub( /^_/, '' )}"
									open( "#{@dst_dir}/#{cache}", 'w' ){|f| f.write img_file}
									img.set_attribute( 'src', cache )
								rescue OpenURI::HTTPError
									$stderr.puts "skipped an image: #{TOP}#{org}"
								end
							end
							f.puts contents.inner_html
							f.puts html_footer
						end
					rescue
						$stderr.puts "#{$!.class}: #$!"
						$stderr.puts "skipped an article: #{item.uri}"
					end
				end
				
				#
				# generating TOC in html
				#
				open( "#{@dst_dir}/toc.html", 'w:utf-8' ) do |f|
					f.write html_header( 'Table of Contents' )
					f.puts "<ul>"
					items.each do |item|
						f.puts %Q|\t<li><a href="#{item_id item.uri}.html">#{item.title}</a></li>|
					end
					f.puts "</ul>"
					f.write html_footer
				end
				
				#
				# generating TOC in ncx
				#
				open( "#{@dst_dir}/toc.ncx", 'w:utf-8' ) do |f|
					f.write <<-XML.gsub( /^\t/, '' )
					<?xml version="1.0" encoding="UTF-8"?>
					<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
					<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
					<docTitle><text>INTERNET Watch (#{now_str})</text></docTitle>
					<navMap>
						<navPoint id="toc" playOrder="0"><navLabel><text>Table of Contents</text></navLabel><content src="toc.html" /></navPoint>
					XML
				
					items.each_with_index do |item, index|
						f.puts %Q|\t\t<navPoint id="#{item_id item.uri}" playOrder="#{index}"><navLabel><text>#{item.title}</text></navLabel><content src="#{item_id item.uri}.html" /></navPoint>|
					end
				
					f.write <<-XML.gsub( /^\t/, '' )
					</navMap>
					</ncx>
					XML
				end
				
				#
				# generating OPF
				#
				open( "#{@dst_dir}/internet-watch.opf", 'w:utf-8' ) do |f|
					f.write <<-XML.gsub( /^\t/, '' )
					<?xml version="1.0" encoding="utf-8"?>
					<package unique-identifier="uid">
						<metadata>
							<dc-metadata xmlns:dc="http://purl.org/metadata/dublin_core" xmlns:oebpackage="http://openebook.org/namespaces/oeb-package/1.0/">
								<dc:Title>INTERNET Watch (#{now_str})</dc:Title>
								<dc:Language>ja-JP</dc:Language>
								<dc:Creator>インプレス</dc:Creator>
								<dc:Description>INTERNET Watch、#{now_str}生成</dc:Description>
								<dc:Date>#{now.strftime( '%d/%m/%Y' )}</dc:Date>
							</dc-metadata>
							<x-metadata>
								<output encoding="utf-8" content-type="text/x-oeb1-document"></output>
								<EmbeddedCover>internet-watch.jpg</EmbeddedCover>
							</x-metadata>
						</metadata>
						<manifest>
							<item id="toc" media-type="application/x-dtbncx+xml" href="toc.ncx"></item>
							<item id="style" media-type="text/css" href="internet-watch.css"></item>
							<item id="index" media-type="text/html" href="toc.html"></item>
					XML
				
					items.each do |item|
						f.puts %Q|\t\t<item id="#{item_id item.uri}" media-type="text/html" href="#{item_id item.uri}.html"></item>|
					end
				
					f.write <<-XML.gsub( /^\t/, '' )
					</manifest>
					<spine toc="toc">
						<itemref idref="index" />
					XML
				
					items.each do |item|
						f.puts %Q|\t<itemref idref="#{item_id item.uri}" />\n|
					end
				
					f.write <<-XML.gsub( /^\t/, '' )
					</spine>
					<tours></tours>
					<guide>
					  <reference type="toc" title="Table of Contents" href="toc.html"></reference>
					  <reference type="start" title="Table of Contents" href="toc.html"></reference>
					</guide>
					</package>
					XML
				end

				yield "#{@dst_dir}/internet-watch.opf"
			end

		private

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
						sleep 1
						retry
					end
				end
			end
			
			def item_id( uri )
				File::basename( uri.path, '.html' )
			end
			
			def get_article( uri )
				cache = "#{@src_dir}/#{File::basename uri.path}"
				begin
					html = open( cache, 'r:Shift_JIS', &:read )
				rescue Errno::ENOENT
					#puts "getting article: #{uri.path}".encode( Encoding::default_external )
					html = retry_loop( 5 ) do
						open( uri, 'r:Shift_JIS', &:read )
					end
					open( cache, 'w' ){|f| f.write html }
				end
				Nokogiri( html.encode 'UTF-8', invalid: :replace, undef: :replace, replace: '?' )
			end
			
			def html_header( title )
				<<-HTML.gsub( /^\t/, '' )
				<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
				<html>
				<head>
					<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"></meta>
					<title>#{title}</title>
					<link rel="stylesheet" href="internet-watch.css" type="text/css" media="all"></link>
				</head>
				<body>
					<h1>#{title}</h1>
				HTML
			end
			
			def html_footer
				<<-HTML.gsub( /^\t/, '' )
				</body>
				</html>
				HTML
			end
		end
	end
end
