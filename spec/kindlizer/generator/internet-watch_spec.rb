# -*- coding: utf-8 -*-

require './lib/kindlizer/backend/dup_checker'
require File.expand_path('../../../../lib/kindlizer/generator/internet-watch', __FILE__ )

describe 'internet-watch generator' do
	context 'normal' do
		it 'makes OPF file' do
			Dir.mktmpdir do |dir|
				Kindlizer::Generator::InternetWatch::new( dir ).generate( Time::now ) do |opf|
					opf.should eq "#{dir}/dst/internet-watch.opf"
				end
			end
		end
	end
end
