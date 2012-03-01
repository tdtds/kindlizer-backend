# -*- coding: utf-8; -*-
#
# kindlizer-backend.rb : backend process of kindlizer service.
#
# Copyright (C) 2011 by TADA Tadashi <t@tdtds.jp>
#
require 'clockwork'
require 'uri'
require 'open-uri'
require 'yaml'
require 'kindlegen'
require 'pathname'
require 'mail'

$: << './lib'

module KindlizerBackend
	class Config
		def initialize( uri )
			@uri = URI( uri )
			@conf = {}
			load
		end

		def []( key )
			@conf[key.to_sym]
		end

		def task( hour )
			@conf[:task][hour.to_i] || []
		end

		def replace( conf_new )
			conf_new.update( @conf )
		end

	protected
		def update( hash )
			hash.update( @conf )
		end

	private
		def load
			@conf = YAML::load( open( @uri, {:proxy => nil}, &:read ) )
		end
	end

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

	def self.exec_task( conf )
		now = Time::now
		p "Staring action on #{now}."

		# relaoding config
		begin
			conf_new = Config::new( ENV['KINDLIZER_CONFIG'] )
			conf.replace( conf_new )
		rescue
			p 'failed config reloading, then using previous settings.'
		end

		# executing tasks
		conf.task( now.hour ).each do |task|
			Task::new( task ).run( conf[:mailto], conf[:mailfrom] )
		end
	end

	Clockwork::handler do |time|
		exec_task( time )
	end

	conf = Config::new( ENV['KINDLIZER_CONFIG'] )

	if ENV['RACK_ENV'] == 'production'
		Mail.defaults do # using sendgrid plugin
			delivery_method :smtp, {
				:address => 'smtp-a.css.fujitsu.com',
				:port => '25',
				:domain => 'heroku.com',
				:user_name => ENV['SENDGRID_USERNAME'],
				:password => ENV['SENDGRID_PASSWORD'],
				:authentication => :plain,
				:enable_starttls_auto => true
			}
		end
		Clockwork::every( 1.hour, conf, :at => '*:04' )
	else
		raise 'cannot found ENV["SMTP"].' unless ENV['SMTP']
		server, port = ENV['SMTP'].split( /:/ )
		Mail.defaults do # using sendgrid plugin
			delivery_method :smtp, {
				:address => server,
				:port => (port || '25'),
			}
		end
		Clockwork::every( 1.hour, conf ) ### for testing
	end
end
