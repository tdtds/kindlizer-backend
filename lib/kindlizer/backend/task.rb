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
			@generator = Kindlizer::Generator.const_get( name.split(/-/).map{|a| a.capitalize}.join )
		end

		def run( to, from, now )
			Dir.mktmpdir do |dir|
				@generator::new( dir ).generate( now ) do |opf|
					Kindlegen.run( opf, '-o', 'kindlizer.mobi', '-locale', 'ja' )
					mobi = Pathname( opf ).dirname + 'kindlizer.mobi'
					if mobi.file?
						$logger.info "generated #{mobi} successfully."
						deliver( to, from, mobi )
						$logger.info "sent mail successfully."
					else
						$logger.error 'failed mobi generation.'
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
				attachments[mobi.basename.to_s] = {
					:mime_type => 'application/octet-stream',
					:content => open(mobi, &:read)
				}
			end
		end
	end
end
