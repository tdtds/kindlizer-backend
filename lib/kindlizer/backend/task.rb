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
					else
						$logger.error 'failed mobi generation.'
					end
				end
			end
		end

	private
		def deliver( to_address, from_address, mobi )
			if to_address =~ /^dropbox:/
				deliver_via_dropbox(to_address.sub(/^dropbox:/, ''), mobi)
			else
				deliver_via_mail(to_address, from_address, mobi)
			end
		end

		def deliver_via_mail(to_address, from_address, mobi)
			Mail.deliver do
				from from_address
				to  to_address
				subject 'sent by kindlizer'
				body 'dummy text'
				attachments[mobi.basename.to_s] = {
					:mime_type => 'application/octet-stream',
					:content => open(mobi, &:read)
				}
			end
			$logger.info "sent mail successfully."
		end

		def deliver_via_dropbox(to_address, mobi)
			require 'dropbox_sdk'

			session = DropboxSession.new(ENV['DROPBOX_APP_KEY'], ENV['DROPBOX_APP_SECRET'])
			session.set_request_token(ENV['DROPBOX_REQUEST_TOKEN_KEY'], ENV['DROPBOX_REQUEST_TOKEN_SECRET'])
			session.set_access_token(ENV['DROPBOX_ACCESS_TOKEN_KEY'], ENV['DROPBOX_ACCESS_TOKEN_SECRET'])
			client = DropboxClient.new(session, :dropbox)
			open(mobi) do |f|
				path = Pathname(to_address) + "#{mobi.basename('.mobi').to_s}#{Time::now.to_i}.mobi"
				client.put_file(path.to_s, f)
			end
			$logger.info "saved to dropbox successfully."
		end
	end
end
