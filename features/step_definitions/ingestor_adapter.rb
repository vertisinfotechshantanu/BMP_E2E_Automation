require 'net/scp'
require 'net/ssh'
require 'logger'
require 'ooyala-v2-api'
require 'JSON'

Given(/^crete new XML set$/) do
	testXML = E2E.new
	testXML.crete_xml
end

Then(/^ssh to the instance$/)do
	testXML = E2E.new
	testXML.ssh_AWS
end

Then(/^create the final HASH$/)do
	testXML = E2E.new
	testXML.create_hash
end

Then(/^check data$/)do
	testXML = E2E.new
	testXML.check_data
end


class E2E
	$file_array = ['./features/step_definitions/XML/tv_eps_fpe.xml','./features/step_definitions/XML/tv_eps_asset.xml','./features/step_definitions/XML/tv_eps_trailer.xml','./features/step_definitions/XML/movie_fpe.xml','./features/step_definitions/XML/movie_asset.xml','./features/step_definitions/XML/movie_trailer.xml','./features/step_definitions/XML/tv_no_eps_fpe.xml','./features/step_definitions/XML/tv_no_eps_asset.xml','./features/step_definitions/XML/tv_no_eps_trailer.xml']
	$asset_ids = []
	$progid = []
	$bmp_element = {}
	$bmp_element1 = {}
	
	def crete_xml

		flag = 0	
		$file_array.each do |file|
			if flag%3 == 0
				$replace = Time.now.strftime('%s') 
			end
			thiz = File.read("#{file}")
			if file.include?("trailer")
				flag = flag + 1
				#thiz.gsub(/assetId="\w+"/) {|value|	puts "value of asset id is #{value} with $replace value is #{$replace}"}
				File.open("#{file}", "w") {|file| file.puts thiz.gsub(/assetId="\w+"/, "assetId=\"#{$replace}_T\"")}
			elsif file.include?("fpe")
				flag = flag + 1
				thiz = thiz.gsub(/assetId="\d+"/, "assetId=\"#{$replace}\"")
				thiz = thiz.gsub(/assetId="\d+_T"/, "assetId=\"#{$replace}_T\"")
				thiz = thiz.gsub(/packageId="\d+"/, "packageId=\"#{$replace}\"")
				thiz = thiz.gsub(/programmeId="\d+"/, "programmeId=\"#{$replace}\"")
				sleep(1)
				thiz = thiz.gsub(/showID="\d+"/, "showID=\""+Time.now.strftime('%s')+"\"")
				sleep(1)
				thiz = thiz.gsub(/groupID="\d+"/, "groupID=\""+Time.now.strftime('%s')+"\"")
				thiz = thiz.gsub(/<SeasonNumber>\d+<\/SeasonNumber>/, "<SeasonNumber>"+rand(999).to_s+"</SeasonNumber>")
				thiz.gsub(/E2EAutomationAsset\w+_/) {|value| thiz = thiz.gsub(/<Title>E2EAutomationAsset\w+_\d+<\/Title>/, "<Title>#{value}#{$replace}</Title>")}
				File.open("#{file}", "w") {|file| file.puts thiz.gsub(/<EpisodeTitle>E2EAutomationEpisode_\d+<\/EpisodeTitle>/, "<EpisodeTitle>E2EAutomationEpisode_#{$replace}<\/EpisodeTitle>")}
			elsif file.include?("asset")
				flag = flag + 1
				File.open("#{file}", "w") {|file| file.puts thiz.gsub(/assetId="\d+"/, "assetId=\"#{$replace}\"")}
			end
		end
	end

	def ssh_AWS
		scp = Net::SCP.start("#{ENV['Instance']}", "#{ENV['User']}", :keys => [ "#{ENV['PEM']}" ])
		$file_array.each do |file|
		 	scp.upload! "#{file}", "/home/ec2-user/"
		 	#link used http://stackoverflow.com/questions/14658363/proxy-tunnel-through-multiple-systems-with-ruby-netssh
	 	end
		puts "File uploaded ..." 
		Net::SSH.start("#{ENV['Instance']}", "#{ENV['User']}", :keys => [ "#{ENV['PEM']}" ]) do |session|
			puts "Clearing Backlot queue ..."
			session.exec!("drush queue-run foxtel_backlot --root=/var/www/foxtel-cms/www")
			puts "Clearing log file ..."
			session.exec!("sudo rm -rf #{ENV['LogFile']}")
			session.exec!("sudo /etc/init.d/ingestadapter restart")
			sleep 5
			#p "ingestor started"		
			session.exec!("sudo mv /home/ec2-user/*.xml /mnt/ingestion_media/Samples")
			do_tail session, "#{ENV['LogFile']}"
		end
	end

	def do_tail session, file
		temp_hash = {}
		$error_count = 0
		$warning_count = 0
		session.open_channel do |channel|
			channel.on_data do |ch, data|
				#puts "Length of the temp hash is #{temp_hash.length}"
				if data.include?('Sending embed code to CMS with body:')
					data.gsub(/\d+_\w+/).each do |key| temp_hash[":#{key}"] = JSON.parse(data.split('body:')[1])['embedCode'] end
				end
				if (data.include?('ERROR -- :') && data.include?('Halted Asset')) || data.include?('Retries left: 0')
					$error_count = $error_count + 1

					if data.include?('Halted Asset') && data.include?('BPUploadXMLToCMS') && data.include?('asset.xml')
						$error_count = $error_count + 1
					end
					puts "Error count increased to #{$error_count}"
				elsif data.include?("WARN -- :")
					puts "Warning  count increased to #{$warning_count}"
				end
				puts "Temp hash length  #{temp_hash.length}"
				if (temp_hash.length + $error_count) == $file_array.length
					$bmp_element1[:assetIds] = temp_hash
					channel.close
					session.exec!("sudo /etc/init.d/ingestadapter restart")
				end	
			end
			channel.exec "tail -f #{file}"
		end
	end

	def create_hash
		flag = 0
		$file_array.each do |file1|
			file = File.read("#{file1}")
			supported_device = []
			videoFormat = []
			if file1.include?('fpe')
				flag = flag + 1
 				file.gsub(/start="\d+-\d+-\d+T\d+:\d+:\d+.\d+Z/).each do |key| $bmp_element[:start_date] = key.split('"')[1] end
				file.gsub(/end="\d+-\d+-\d+T\d+:\d+:\d+.\d+Z/).each do |key| $bmp_element[:end_date] = key.split('"')[1] end
				file.gsub(/offerType="\w+-\w+-\w+/).each do |key| $bmp_element[:offerType] = key.split('"')[1] end
				file.gsub(/deviceId="\w+"/).each do |key| supported_device << key.split('"')[1] end
				$bmp_element[:deviceId] = supported_device 
				file.gsub(/showID="\d+"/).each do |key| $bmp_element[:showID] = key.split('"')[1] end
				file.gsub(/category="\w+"/).each do |key| $bmp_element[:category] = key.split('"')[1] end
				file.gsub(/programmeId="\d+"/).each do |key| 
					$bmp_element[:programmeId] = key.split('"')[1] 
					$progid << key.split('"')[1]
				end
				file.gsub(/providerId="\w+"/).each do |key| $bmp_element[:providerId] = key.split('"')[1] end
				file.gsub(/groupID="\d+"/).each do |key| $bmp_element[:groupId] = key.split('"')[1] end
				file.gsub(/<Title>\w+\w+<\/Title>/).each do |key| $bmp_element[:Title] = key.split('>')[1].split('<')[0] end
				file.gsub(/<VideoFormat>\w+\w+<\/VideoFormat>/).each do |key| videoFormat << key.split('>')[1].split('<')[0] end	
				$bmp_element[:VideoFormat] = videoFormat
				file.gsub(/<Genre main=\"1\" sub=\"2\">\w+:\w+<\/Genre>/).each do |key| $bmp_element[:genre] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<ParentalRating>\w+<\/ParentalRating>/).each do |key| $bmp_element[:MaturityRating] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<Subtitled>\w+<\/Subtitled>/).each do |key| $bmp_element[:Subtitled] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<Year>\d+<\/Year>/).each do |key| $bmp_element[:Year] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<Colour>\w+<\/Colour>/).each do |key| $bmp_element[:Colour] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<Languages>\w+<\/Languages>/).each do |key| $bmp_element[:Languages] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<Country>\w+<\/Country>/).each do |key| $bmp_element[:Country] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<Credit role=\"Director\"><Person>\w+ \w+<\/Person>/).each do |key| $bmp_element[":#{key.split('"')[1]}"] = key.split('"')[2].split('>')[2].split('<')[0] end
				file.gsub(/<Credit role=\"Actor\"><Person>\w+ \w+<\/Person>/).each do |key| $bmp_element[":#{key.split('"')[1]}"] = key.split('"')[2].split('>')[2].split('<')[0] end
				file.gsub(/<Credit role=\"Writer\"><Person>\w+ \w+<\/Person>/).each do |key| $bmp_element[":#{key.split('"')[1]}"] = key.split('"')[2].split('>')[2].split('<')[0] end
				file.gsub(/<SeasonNumber>\d+<\/SeasonNumber>/).each do |key| $bmp_element[:SeasonNumber] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<EpisodeNumber>\d+<\/EpisodeNumber>/).each do |key| $bmp_element[:EpisodeNumber] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<EpisodeTitle>\w+\w+<\/EpisodeTitle>/).each do |key| $bmp_element[:EpisodeTitle] = key.split('>')[1].split('<')[0] end	
				file.gsub(/<ShortSynopsis>[\w+\s*\w+]*<\/ShortSynopsis>/).each do |key| $bmp_element[:ShortSynopsis] = key.split('>')[1].split('<')[0] end
				file.gsub(/<LongSynopsis>[\w+\s*\w+]*<\/LongSynopsis>/).each do |key| $bmp_element[:LongSynopsis] = key.split('>')[1].split('<')[0] end
			elsif file1.include?('asset')
				flag = flag + 1
				file.gsub(/assetId="\d+"/).each do |key| $bmp_element[:assetId] = key.split('"')[1].split('"')[0] end
				file.gsub(/<Duration>\w+.\w+<\/Duration>/).each do |key| $bmp_element[:Duration] = key.split('>')[1].split('<')[0] end
				file.gsub(/<AspectRatio>\d+x\d+<\/AspectRatio>/).each do |key| $bmp_element[:AspectRatio] = key.split('>')[1].split('<')[0] end
				file.gsub(/<Sound>\w+<\/Sound>/).each do |key| $bmp_element[:Sound] = key.split('>')[1].split('<')[0] end
			elsif file1.include?('trailer')
				flag = flag + 1
				file.gsub(/assetId="\d+_T"/).each do |key| $bmp_element[:trailerId] = key.split('"')[1].split('"')[0] end
			end
			if flag == 3
				$bmp_element1[:programeIds] = $progid
				$bmp_element1["#{$bmp_element[:programmeId]}"] = $bmp_element
				$bmp_element = {}
				flag = 0 
			end
		end
		raise "Ingestion Process faild because assets are not ingeted" if !$bmp_element1.include?(:assetIds)
		check_data
	end

	def check_data
		#puts "in function"
		$bmp_element1 = {:assetIds=>{":1446465242_T_SD"=>"VwbGdreDrnnnjdRgpId6T8S7mZdeheeZ", ":1446465240_SD"=>"VybGdreDo0ppgtLVx0R0JAD9ZCD4vCjC", ":1446465240_T_SD"=>"V2bGdreDptIReAruFwtQNre3k5eqIQjY", ":1446465240_HD"=>"V0bGdreDprKWbdbsJK-OhhCUSBSlPWnf", ":1446465242_HD"=>"V4bGdreDrYSkY9Ici6ZPtQHgYzOD0W1Z", ":1446465242_SD"=>"UwbWdreDpPho9IU8lK8IWifbzzrtt9b3", ":1_lErhx7lWemkSAMqTIAt"=>"twbmdreDpdl1_lErhx7lWemkSAMqTIAt"}, :programeIds=>["1446465240", "1446465242"]}
#		puts "#{$bmp_element1[:programeIds]}"
		@@api = Ooyala::API.new("#{ENV['API']}","#{ENV['Secret']}")
		$bmp_element1[:programeIds].each do |key|
			if !($bmp_element1[:assetIds].include?(":#{key}_HD") && $bmp_element1[:assetIds].include?(":#{key}_SD") && $bmp_element1[:assetIds].include?(":#{key}_T_SD"))
 #				puts 'doing something'
				$bmp_element1[:programeIds].delete("#{key}")
				$bmp_element1.delete("#{key}")
				$bmp_element1[:assetIds].each do |keyDel|
					$bmp_element1[:assetIds].delete("#{keyDel[0]}") if keyDel[0].include?("#{key}")
				end
#				puts "#{$bmp_element1[:assetIds]}"
#				puts "#{$bmp_element1[:programeIds]}"
			end
		end	
		$bmp_element1[:assetIds].each do |key|
			if !(key[0].include?('_T_SD') || key[0].include?('_SD') || key[0].include?('_HD'))
				p 'Deleting Garbage value found in HASH :' +"#{key[0]}"
				$bmp_element1[:assetIds].delete("#{key[0]}")
				break
			end

			puts "Checking Status for Ingestd assets"
			puts @@api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status']
			if @@api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status'] != 'live'
				p 'Waiting till satus of the asset trascoding to LIVE'
				patch_body = {:post_processing_status => 'live', :status => 'live'}
				response = @@api.patch("/v2/assets/#{$bmp_element1[:assetIds][key[0]]}",patch_body,{})
				sleep(60)
				puts 'Now status is :' + @@api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status']
			end
			puts "Staus of key in the Backlot is :"+ @@api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status']
			puts "___________________________________"
			
		end
		puts "#{$bmp_element1}"
	end
end