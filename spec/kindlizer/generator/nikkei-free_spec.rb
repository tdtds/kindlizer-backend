# -*- coding: utf-8 -*-

require File.expand_path('../../../../lib/kindlizer/generator/nikkei-free', __FILE__ )

describe 'nikkei-free generator' do
	context 'normal' do
		it 'makes OPF file' do
			Dir.mktmpdir do |dir|
				Kindlizer::Generator::NikkeiFree::new( dir ).generate( Time::now ) do |opf|
					opf.should eq "#{dir}/dst/nikkei-free.opf"
				end
			end
		end
	end
end
