# -*- coding: utf-8; -*-
#
# kindlizer-backend.rb : backend process of kindlizer service.
#
# Copyright (C) 2011 by TADA Tadashi <t@tdtds.jp>
#
require 'clockwork'

module KindlizerBackend
	def self.exec_task( time )
		p time
	end

	Clockwork::handler do |time|
		exec_task( time )
	end

	Clockwork::every( 1.hour, Time::now, :at => '*:04' )
end
