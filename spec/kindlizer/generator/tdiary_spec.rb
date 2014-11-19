# -*- coding: utf-8 -*-

ENV['TDIARY_TOP'] = 'http://sho.tdiary.net/'

require File.expand_path('../../../../lib/kindlizer/generator/tdiary', __FILE__ )
require 'tmpdir'

describe 'tdiary generator' do
	context 'normal' do
		it 'makes OPF file' do
			Dir.mktmpdir do |dir|
				opts = {now: Time.now, 'tdiary_top' => 'http://sho.tdiary.net/'}
				Kindlizer::Generator::Tdiary::new(dir).generate(opts) do |opf|
					expect(opf).to eq "#{dir}/tdiary.opf"
				end
			end
		end
	end
end
