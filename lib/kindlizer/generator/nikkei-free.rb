# -*- coding: utf-8; -*-
#
# scraping nikkei.com (for free user) for Kindlizer
#

require 'nokogiri'
require 'open-uri'
require 'tmpdir'
require 'pathname'
require  (File.dirname(__FILE__) + '/nikkei-paid')

module Kindlizer
	module Generator
		class NikkeiFree < NikkeiPaid
			def auth
				return nil, nil
			end
		end
	end
end
