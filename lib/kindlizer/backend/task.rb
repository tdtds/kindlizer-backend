# -*- coding: utf-8; -*-
#
# task controller
#
# Copyright (C) 2012 by TADA Tadashi <t@tdtds.jp>
# Distributed under GPL.
#
require 'kindlegen'
require 'mail'

module Kindlizer::Backend
	class Task
		def initialize( name )
			require "kindlizer/generator/#{name}"
			@generator = Kindlizer::Generator.const_get( name.capitalize.gsub( /-(.)/ ){|s|$1.capitalize} )
		end

		def run( to, from )
			Dir.mktmpdir do |dir|
				@generator::new( dir ).generate do |opf|
					Kindlegen.run( opf, '-o', 'kindlizer.mobi' )
					mobi = Pathname( opf ).dirname + 'kindlizer.mobi'
					if mobi.file?
						p "generated #{mobi} successfully."
						deliver( to, from, mobi )
					else
						p 'failed mobi generation.'
					end
				end
			end
		end

		def deliver( to_address, from_address, mobi )
			Mail.deliver do
				from from_address
				to  to_address
				subject 'sent by kindlizer'
				body ''
				add_file mobi.to_s
			end
		end
	end
end
