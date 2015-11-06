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

# This class contains code for Ingestion process
class E2E
  # This function creates XML file to upload on AWS watchfolder using predefined tamplate XMLs
  def crete_xml
    puts "Shantanu please change instance to EBS-27"
    flag = 0
    $file_array.each do |file|
      $replace = Time.now.strftime('%s') if flag % 3 == 0
      puts "value of $replace is #{$replace}"
      thiz = File.read("#{file}")
      if file.include?('trailer')
        flag += 1
        File.open("#{file}", 'w') { |file| file.puts thiz.gsub(%r{assetId="\w+"}, "assetId=\"#{$replace}_T\"") }
      elsif file.include?('fpe')
        flag += 1
        create_fpe_xml thiz, file, $replace
      elsif file.include?('asset')
        flag += 1
        File.open("#{file}", 'w') { |file| file.puts thiz.gsub(%r{assetId="\d+"}, "assetId=\"#{$replace}\"") }
      end
    end
  end

  # This function uploads created XML files to the AWS watchfolder and starts the ingestor
  def ssh_AWS
    scp = Net::SCP.start("#{ENV['Instance']}", "#{ENV['User']}", :keys => ["#{ENV['PEM']}"])
    # link used http://stackoverflow.com/questions/14658363/proxy-tunnel-through-multiple-systems-with-ruby-netssh
    $file_array.each { |file| scp.upload! "#{file}", '/home/ec2-user/'}
    p 'File uploaded ...'
    Net::SSH.start("#{ENV['Instance']}", "#{ENV['User']}", :keys => ["#{ENV['PEM']}"]) do |session|
      p 'Clearing Backlot queue ...'
      session.exec!('drush queue-run foxtel_backlot --root=/var/www/foxtel-cms/www')
      session.exec!("sudo rm -rf #{ENV['LogFile']}")
      session.exec!('sudo /etc/init.d/ingestadapter restart')
      sleep 5
      #session.exec!("sudo mv /home/ec2-user/*.xml #{ENV['WatchFolder']}" )
      do_tail session, "#{ENV['LogFile']}"
    end
  end

  # This function tails the log file and displays the Ingestion progress on the console 
  def do_tail (session, file)
    temp_hash = {}
    session.open_channel do |channel|
      channel.on_data do |_ch, data|
        data.gsub(%r{\d+_\w+}).each { |key| temp_hash[":#{key}"] = JSON.parse(data.split('body:')[1])['embedCode'] } if data.include?('Sending embed code to CMS with body:')
        if (data.include?('ERROR -- :') && data.include?('Halted Asset')) || data.include?('Retries left: 0')
          $error_count += 1
          $error_count += 1 if data.include?('Halted Asset') && data.include?('BPUploadXMLToCMS') && data.include?('asset.xml')
        elsif data.include?('WARN -- :')
           $warning_count += 1
        end
        clear_screen temp_hash.length
        if (temp_hash.length + $error_count) == $file_array.length
          $bmp_element1[:assetIds] = temp_hash
          channel.close
          session.exec!('sudo /etc/init.d/ingestadapter restart')
        end
      end
      channel.exec "tail -f #{file}"
    end
  end

  # This function will create HASH file from predefined XML files and values from ingested assets
  def create_hash
    flag = 0
    $file_array.each do |file1|
      file = File.read("#{file1}")
      supported_device = []
      videoFormat = []
      if file1.include?('fpe')
        flag += 1
        file.gsub(%r{start="\d+-\d+-\d+T\d+:\d+:\d+.\d+Z}).each { |key| $bmp_element[:start_date] = key.split('"')[1] }
        file.gsub(%r{end="\d+-\d+-\d+T\d+:\d+:\d+.\d+Z}).each { |key| $bmp_element[:end_date] = key.split('"')[1] }
        file.gsub(%r{offerType="\w+-\w+-\w+}).each { |key| $bmp_element[:offerType] = key.split('"')[1] }
        file.gsub(%r{deviceId="\w+"}).each { |key| supported_device << key.split('"')[1] }
        $bmp_element[:deviceId] = supported_device
        file.gsub(%r{showID="\d+"}).each { |key| $bmp_element[:showID] = key.split('"')[1] }
        file.gsub(%r{category="\w+"}).each { |key| $bmp_element[:category] = key.split('"')[1] }
        file.gsub(%r{programmeId="\d+"}).each do |key|
          $bmp_element[:programmeId] = key.split('"')[1]
          $progid << key.split('"')[1]
        end
        file.gsub(%r{providerId="\w+"}).each { |key| $bmp_element[:providerId] = key.split('"')[1] }
        file.gsub(%r{groupID="\d+"}).each { |key| $bmp_element[:groupId] = key.split('"')[1] }
        file.gsub(%r{<Title>\w+\w+<\/Title>}).each { |key| $bmp_element[:Title] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<VideoFormat>\w+\w+</VideoFormat>}).each { |key| videoFormat << key.split('>')[1].split('<')[0] }
        $bmp_element[:VideoFormat] = videoFormat
        file.gsub(%r{<Genre main=\"1\" sub=\"2\">\w+:\w+</Genre>}).each { |key| $bmp_element[:genre] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<ParentalRating>\w+</ParentalRating>}).each { |key| $bmp_element[:MaturityRating] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<Subtitled>\w+</Subtitled>}).each { |key| $bmp_element[:Subtitled] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<Year>\d+</Year>}).each { |key| $bmp_element[:Year] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<Colour>\w+</Colour>}).each { |key| $bmp_element[:Colour] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<Languages>\w+</Languages>}).each { |key| $bmp_element[:Languages] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<Country>\w+</Country>}).each { |key| $bmp_element[:Country] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<Credit role=\"Director\"><Person>\w+ \w+</Person>}).each { |key| $bmp_element[:Director] = key.split('"')[2].split('>')[2].split('<')[0] }
        file.gsub(%r{<Credit role=\"Actor\"><Person>\w+ \w+</Person>}).each { |key| $bmp_element[:Actor] = key.split('"')[2].split('>')[2].split('<')[0] }
        file.gsub(%r{<Credit role=\"Writer\"><Person>\w+ \w+</Person>}).each { |key| $bmp_element[:Writer] = key.split('"')[2].split('>')[2].split('<')[0] }
        file.gsub(%r{<SeasonNumber>\d+</SeasonNumber>}).each { |key| $bmp_element[:SeasonNumber] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<EpisodeNumber>\d+</EpisodeNumber>}).each { |key| $bmp_element[:EpisodeNumber] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<EpisodeTitle>\w+\w+</EpisodeTitle>}).each { |key| $bmp_element[:EpisodeTitle] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<ShortSynopsis>[\w+\s*\w+]*</ShortSynopsis>}).each { |key| $bmp_element[:ShortSynopsis] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<LongSynopsis>[\w+\s*\w+]*</LongSynopsis>}).each { |key| $bmp_element[:LongSynopsis] = key.split('>')[1].split('<')[0] }
      elsif file1.include?('asset')
        flag += 1
        file.gsub(%r{assetId="\d+"}).each { |key| $bmp_element[:assetId] = key.split('"')[1].split('"')[0] }
        file.gsub(%r{<Duration>\w+.\w+</Duration>}).each { |key| $bmp_element[:Duration] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<AspectRatio>\d+x\d+</AspectRatio>}).each { |key| $bmp_element[:AspectRatio] = key.split('>')[1].split('<')[0] }
        file.gsub(%r{<Sound>\w+<\/Sound>}).each { |key| $bmp_element[:Sound] = key.split('>')[1].split('<')[0] }
      elsif file1.include?('trailer')
        flag += 1
        file.gsub(%r{assetId="\d+_T"}).each { |key| $bmp_element[:trailerId] = key.split('"')[1].split('"')[0] }
      end
      if flag == 3
        $bmp_element1[:programeIds] = $progid
        $bmp_element1["#{$bmp_element[:programmeId]}"] = $bmp_element
        $bmp_element = {}
        flag = 0
      end
    end
    fail 'Ingestion Process faild because assets are not ingeted' unless $bmp_element1.include?(:assetIds)
    check_data
  end

  # This function will check data for any garbage value or removes programme ids which are not ingested completely
  def check_data
    @api = Ooyala::API.new("#{ENV['API']}", "#{ENV['Secret']}")
    $bmp_element1[:programeIds].each do |key|
      unless $bmp_element1[:assetIds].include?(":#{key}_HD") && $bmp_element1[:assetIds].include?(":#{key}_SD") && $bmp_element1[:assetIds].include?(":#{key}_T_SD")
        $bmp_element1[:programeIds].delete("#{key}")
        $bmp_element1.delete("#{key}")
        $bmp_element1[:assetIds].each { |keyDel| $bmp_element1[:assetIds].delete("#{keyDel[0]}") if keyDel[0].include?("#{key}") }
      end
    end
    $bmp_element1[:assetIds].each do |key|
      unless key[0].include?('_T_SD') || key[0].include?('_SD') || key[0].include?('_HD')
        p 'Deleting Garbage value found in HASH :' + "#{key[0]}"
        $bmp_element1[:assetIds].delete("#{key[0]}")
        next
      end
      p 'Checking Status for Ingestd assets'
      puts @api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status']
      if @api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status'] != 'live'
        p 'Waiting till satus of the asset trascoding to LIVE'
        patch_body = { post_processing_status: 'live', status:  'live' }
        @api.patch("/v2/assets/#{$bmp_element1[:assetIds][key[0]]}", patch_body, {})
        sleep(60)
        puts 'Now status is :' + @api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status']
      end
      p 'Staus of key in the Backlot is :' + @api.get("assets/#{$bmp_element1[:assetIds][key[0]]}")['status']
      p '___________________________________'
    end
    puts "#{$bmp_element1}"
  end

  def create_fpe_xml(thiz, file, replace)
    thiz = thiz.gsub(%r{assetId="\d+"}, "assetId=\"#{replace}\"")
    thiz = thiz.gsub(%r{assetId="\d+_T"}, "assetId=\"#{replace}_T\"")
    thiz = thiz.gsub(%r{packageId="\d+"}, "packageId=\"#{replace}\"")
    thiz = thiz.gsub(%r{programmeId="\d+"}, "programmeId=\"#{replace}\"")
    thiz = thiz.gsub(%r{showID="\d+"}, "showID=\"" + Time.now.strftime('%s') + "\"")
    sleep(1)
    thiz = thiz.gsub(%r{groupID="\d+"}, "groupID=\"" + Time.now.strftime('%s') + "\"")
    thiz = thiz.gsub(%r{<SeasonNumber>\d+<\/SeasonNumber>}, '<SeasonNumber>' + rand(999).to_s + '</SeasonNumber>')
    thiz.gsub(%r{E2EAutomationAsset\w+_}) { |value| thiz = thiz.gsub(%r{<Title>E2EAutomationAsset\w+_\d+<\/Title>}, "<Title>#{value}#{replace}</Title>") }
    File.open("#{file}", 'w') do |file|
      file.puts thiz.gsub(%r{<EpisodeTitle>E2EAutomationEpisode_\d+<\/EpisodeTitle>}, "<EpisodeTitle>E2EAutomationEpisode_#{replace}<\/EpisodeTitle>") 
    end
  end

  def clear_screen(len)
    (system 'clear')
    puts "Error count is #{$error_count}"
    puts "Warning  count is #{$warning_count}"
    puts "Number of assets ingested : #{len}"
    puts 'I am waiting for Ingetion process to complete ...'
  end
end
