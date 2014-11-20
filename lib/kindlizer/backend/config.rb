# -*- coding: utf-8; -*-
#
# configuration management
#
# Copyright (C) 2012 by TADA Tadashi <t@tdtds.jp>
# Distributed under GPL.
#
require 'yaml'
require 'open-uri'
require 'pathname'

module Kindlizer::Backend
	class ConfigError < StandardError; end

	class Config
		def initialize( uri )
			@uri = uri
			@conf = {}
			load
		end

		def []( key )
			@conf[key.to_sym]
		end

		def task( hour )
			@conf[:schedule][hour.to_i] || []
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
			raise ConfigError.new("Update config file because it is old format.") if @conf[:task]
		end
	end
end
