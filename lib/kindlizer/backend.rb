# -*- coding: utf-8; -*-
#
# configuration management
#
# Copyright (C) 2012 by TADA Tadashi <t@tdtds.jp>
# Distributed under GPL.
#
module Kindlizer
	module Backend
		require 'logger'
		$logger = Logger::new( STDOUT )
		$logger.level = Logger::INFO
		$logger.formatter = proc{|severity, datetime, progname, msg|
			"#{severity}: #{msg}\n"
		}

		require 'kindlizer/backend/config'
		require 'kindlizer/backend/task'
	end
end
