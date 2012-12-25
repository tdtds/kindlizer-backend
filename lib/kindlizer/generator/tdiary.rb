# -*- coding: utf-8; -*-
#
# scraping tDiary's N-Year diary for Kindlizer
#

require 'nokogiri'
require 'open-uri'
require 'uri'

module Kindlizer
	module Generator
		class Tdiary
			TOP = ENV['TDIARY_TOP']
			
			def initialize( tmpdir )
				@current_dir = tmpdir
				FileUtils.cp( "./resource/tdiary.css", @current_dir )
			end

			def generate( now )
				html = retry_loop( 5 ) do
					Nokogiri(open("#{TOP}?date=#{now.strftime '%m%d'}", 'r:utf-8', &:read))
				end
				title = (html / 'head title').text
				author = (html / 'head meta[name="author"]')[0]['content']
				now_str = now.strftime( '%m-%d' )

				#
				# generating html
				#
				html.css('head meta', 'head link', 'head style', 'script').remove
				html.css('div.adminmenu', 'div.sidebar', 'div.footer').remove
				(html / 'img').each do |img|
					file_name = save_image(img['src'])
					img['src'] = file_name
				end
				open( "#{@current_dir}/index.html", 'w' ){|f| f.write html.to_html}

				#
				# generating TOC in ncx
				#
				open( "#{@current_dir}/toc.ncx", 'w:utf-8' ) do |f|
					f.write <<-XML.gsub( /^\t/, '' )
					<?xml version="1.0" encoding="UTF-8"?>
					<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
					<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
					<docTitle><text>tDiary (#{now_str})</text></docTitle>
					<navMap>
						<navPoint id="index" playOrder="1">
							<navLabel>
								<text>#{title}</text>
							</navLabel>
							<content src="index.html" />
						</navPoint>
					</navMap>
					</ncx>
					XML
				end
				
				#
				# generating OPF
				#
				open( "#{@current_dir}/tdiary.opf", 'w:utf-8' ) do |f|
					f.write <<-XML.gsub( /^\t/, '' )
					<?xml version="1.0" encoding="utf-8"?>
					<package unique-identifier="uid">
						<metadata>
							<dc-metadata xmlns:dc="http://purl.org/metadata/dublin_core" xmlns:oebpackage="http://openebook.org/namespaces/oeb-package/1.0/">
								<dc:Title>tDiary (#{now_str})</dc:Title>
								<dc:Language>ja-JP</dc:Language>
								<dc:Creator>#{author}</dc:Creator>
								<dc:Description>tDiary N-Year Diary</dc:Description>
								<dc:Date>#{now.strftime( '%d/%m/%Y' )}</dc:Date>
							</dc-metadata>
						</metadata>
						<manifest>
							<item id="toc" media-type="application/x-dtbncx+xml" href="toc.ncx"></item>
							<item id="style" media-type="text/css" href="tdiary.css"></item>
							<item id="index" media-type="text/html" href="index.html"></item>
						</manifest>
						<spine toc="toc">
							<itemref idref="index" />
						</spine>
						<tours></tours>
						<guide>
							<reference type="start" title="Start Page" href="index.html"></reference>
						</guide>
					</package>
					XML
				end

				yield "#{@current_dir}/tdiary.opf"
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

			def save_image(img)
				img = TOP + img if /^https?:/ !~ img
				uri = URI(img)
				file_name = uri.path.gsub(%r|[/%]|, '_')
				open("#{@current_dir}/#{file_name}", 'w') do |f|
					f.write open(uri, &:read)
				end
				return file_name
			end
		end
	end
end
