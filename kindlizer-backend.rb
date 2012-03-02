# -*- coding: utf-8; -*-
#
# kindlizer-backend.rb : backend process of kindlizer service.
#
# Copyright (C) 2011 by TADA Tadashi <t@tdtds.jp>
#
require 'clockwork'
require 'mail'

$: << './lib'
require 'kindlizer/backend'

module Kindlizer::Backend
	def self.exec_task( conf )
		now = Time::now.utc
		p "Staring action on #{now}."

		# relaoding config
		begin
			conf_new = Config::new( ENV['KINDLIZER_CONFIG'] )
			conf.replace( conf_new )
		rescue
			p 'failed config reloading, then using previous settings.'
		end

		# executing tasks
		s = conf[:tz]
		hour = (now + ((s[1,2].to_i*60 + s[3,2].to_i)*60 * (s[0]+'1').to_i)).hour
 		conf.task( hour ).each do |task|
			p "starting #{task}"
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
				:address => 'smtp.example.com',
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
		require 'pit'
		auth = Pit::get( 'Gmail', :require => {
			'mail' => 'Your Gmail address',
			'pass' => 'Your Gmail Password'
		} )
		Mail.defaults do # using sendgrid plugin
			delivery_method :smtp, {
				address: 'smtp.gmail.com',
				port: '587',
				user_name: auth['mail'],
				password: auth['pass'],
				:authentication => :plain,
				:enable_starttls_auto => true
			}
		end
		Clockwork::every( 1.hour, conf ) ### for testing
	end
end
