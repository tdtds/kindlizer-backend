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
			@conf[:task][hour.to_i]
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

		def run
			Dir.mktmpdir do |dir|
				@generator::new( dir ).generate do |opf|
					p "#{opf} generated!"
				end
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
			Task::new( task ).run
		end
	end

	Clockwork::handler do |time|
		exec_task( time )
	end

	conf = Config::new( ENV['KINDLIZER_CONFIG'] )
	Clockwork::every( 1.hour, conf, :at => '*:04' )
	#Clockwork::every( 1.minute, conf ) ### for testing
end
