# -*- coding: utf-8; -*-
#
# scraping jp.wsj.com for Kindlizer
#

require File.expand_path('../wsj-paid', __FILE__ )

module Kindlizer
	module Generator
		class WsjusPaid < WsjPaid
			TOP = 'http://online.wsj.com'
			LOGIN = "https://id.wsj.com/access/pages/wsj/us/login_standalone.html"

			def generate( now )
				@now = now
				@now_str = now.strftime '%Y-%m-%d %H:%M'
				@title = "WSJ U.S."
				FileUtils.cp( "./resource/wsj-us.jpg", @dst_dir + "/wsj.jpg")

				agent = Mechanize::new
				agent.set_proxy( *ENV['HTTP_PROXY'].split( /:/ ) ) if ENV['HTTP_PROXY']

				toc = []

				agent.get(LOGIN)

				form = agent.page.forms.first
				form.action = ('https://id.wsj.com/auth/submitlogin.json')
				form['username'] = @wsj_id
				form['password'] = @wsj_pw
				agent.page.forms.first.submit

				response = JSON.parse(agent.page.body)
				agent.get( response["url"] )

				agent.get( TOP + "/home-page?_wsjregion=na,us&_homepage=/home/us")

				#
				# scraping top news
				#
				toc_top = ['TOP NEWS']
				(agent.page / "div.whatsNews ul.newsItem h2 a").each do |a|
					if(a.attr('href') =~ /^http:\/\/online.wsj.com\/article\// or a.attr('href') =~ /^\/article\//)
						toc_top << [canonical( a.text.strip ), a.attr( 'href' )]
					end
				end
				toc << toc_top

				#
				# scraping all categories
				(agent.page.root / 'div.wsjMainNav li').each do |li|
					a = (li / 'a').first

					title = a.text.strip
					next if(title == "Home" or title == "Market Data" or title == "C-Suite")

					toc_cat = []
					toc_cat << canonical( title )
					begin
						retry_loop( 5 ) do
							agent.get(a.attr( 'href' ))
							sleep 1
						end
					rescue
						$stderr.puts "cannot get #{uri}."
						raise
					end

					count = 0
					newsLinks = (agent.page / "div.whatsNews ul.newsItem h2 a")
					newsLinks = (agent.page / "div.headlineSummary ul.newsItem h2 a" ) if(newsLinks.size == 0)
					newsLinks.each do |a|
						if(a.attr('href') =~ /^http:\/\/online.wsj.com\/article\// or a.attr('href') =~ /^\/article\//)
							toc_cat << [canonical( a.text.strip ), a.attr( 'href' )]
							count += 1
							break if(count >= 8)
						end
					end
					toc << toc_cat
				end

				begin
					generate_contents( toc, agent )
					yield "#{@dst_dir}/wsj-paid.opf"
				end
			end
		end
	end
end
