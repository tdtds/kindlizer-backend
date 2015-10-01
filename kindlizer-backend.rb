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
require 'kindlizer/backend/dup_checker'

module Kindlizer::Backend
	def self.exec_task( conf )
		# relaoding config
		begin
			conf_new = Config::new( ENV['KINDLIZER_CONFIG'] )
			conf.replace( conf_new )
		rescue
			$logger.warn 'failed config reloading, then using previous settings.'
		end

		# executing tasks
		now = Time::now.localtime( conf[:tz] )
		$logger.info "Staring action on #{now}."
		conf.task( now.hour ).each do |task|
			$logger.info "starting #{task}"

			opts = {:now => now}.update(conf[:tasks][task][:option] || {})
			conf[:tasks][task][:media].each do |media|
				$logger.info "getting media #{media}"
				begin
					Task::new(media).run(conf[:tasks][task][:receiver], conf[:sender], opts)
				rescue
					$logger.error($!)
				end
			end
		end
	end

	Clockwork::handler do |time|
		exec_task( time )
	end

	conf = Config::new( ENV['KINDLIZER_CONFIG'] )

	if ENV['RACK_ENV'] == 'production'
		Mail.defaults do # using sendgrid plugin
			delivery_method :smtp, {
				:address => 'smtp.sendgrid.net',
				:port => '587',
				:domain => 'heroku.com',
				:user_name => ENV['SENDGRID_USERNAME'],
				:password => ENV['SENDGRID_PASSWORD'],
				:authentication => :plain,
				:enable_starttls_auto => true
			}
		end
		if ENV['MONGOLAB_URI']
			DupChecker.setup({clients:{default:{uri:ENV['MONGOLAB_URI']}}})
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
		DupChecker.setup({sessions:{default:{uri:'mongodb://localhost:27017/kindlizer-backend'}}})
		Clockwork::every( 5.minutes, conf ) ### for testing
	end
end
