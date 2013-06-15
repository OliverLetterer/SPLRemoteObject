namespace :test do
  desc "Run the SLRemoteObject Tests for iOS"
  task :ios do
    $ios_success = system("xctool -workspace SLRemoteObject.xcworkspace -scheme 'SLRemoteObjectTests' build -sdk iphonesimulator -configuration Release")
    $ios_success = system("xctool -workspace SLRemoteObject.xcworkspace -scheme 'SLRemoteObjectTests' build-tests -sdk iphonesimulator -configuration Release")
    $ios_success = system("xctool -workspace SLRemoteObject.xcworkspace -scheme 'SLRemoteObjectTests' test -test-sdk iphonesimulator -configuration Release")
  end
  
  desc "Run the SLRemoteObject Tests for Mac OS X"
  task :osx do
    $osx_success = system("xctool -workspace SLRemoteObject.xcworkspace -scheme 'OS X Tests' test -test-sdk macosx -sdk macosx -configuration Release")
  end
end

desc "Run the SLRemoteObject Tests for iOS"
task :test => [ 'test:ios' ] do
  puts "\033[0;31m!! iOS unit tests failed" unless $ios_success
  if $ios_success
    puts "\033[0;32m** All tests executed successfully"
  else
    exit(-1)
  end
end

task :default => 'test'