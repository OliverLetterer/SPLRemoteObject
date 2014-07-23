task :test do
  exit system("xcodebuild -workspace SPLRemoteObject.xcworkspace -scheme 'SLRemoteObjectTests' test -sdk iphonesimulator -configuration Release | xcpretty -c; exit ${PIPESTATUS[0]}")
end

task :default => 'test'
