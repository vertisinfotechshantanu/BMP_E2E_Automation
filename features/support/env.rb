ENV['PEM'] = './features/step_definitions/PemFile/FoxtelEBS-25.pem'
ENV['Instance'] = ''
ENV['User'] = 'ec2-user'
ENV['API'] = ''
ENV['Secret'] = ''
ENV['LogFile'] = '/home/role-ingestor/watch_folder/log_orchestrator.txt'
ENV['WatchFolder'] = '/home/role-ingestor/watch_folder'
$asset_ids = []
$progid = []
$bmp_element = {}
$bmp_element1 = {}
$file_array = ['./features/step_definitions/XML/tv_eps_fpe.xml','./features/step_definitions/XML/tv_eps_asset.xml','./features/step_definitions/XML/tv_eps_trailer.xml','./features/step_definitions/XML/movie_fpe.xml','./features/step_definitions/XML/movie_asset.xml','./features/step_definitions/XML/movie_trailer.xml','./features/step_definitions/XML/tv_no_eps_fpe.xml','./features/step_definitions/XML/tv_no_eps_asset.xml','./features/step_definitions/XML/tv_no_eps_trailer.xml']	
$error_count = 0
$warning_count = 0
