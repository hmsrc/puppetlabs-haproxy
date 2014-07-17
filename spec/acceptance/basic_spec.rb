require 'spec_helper_acceptance'

# C9708 C9709 WONTFIX
describe "configuring haproxy", :unless => UNSUPPORTED_PLATFORMS.include?(fact('osfamily')) do
  # C9961
  describe 'not managing the service' do
    it 'should not listen on any ports' do
      pp = <<-EOS
      class { 'haproxy':
        service_manage => false,
      }
      haproxy::listen { 'stats':
        ipaddress => '127.0.0.1',
        ports     => ['9090','9091'],
        options   => {
          'mode'  => 'http',
          'stats' => ['uri /','auth puppet:puppet'],
        },
      }
      haproxy::listen { 'test00': ports => '80',}
      EOS
      apply_manifest(pp, :catch_failures => true)
    end

    describe port('9090') do
      it { should_not be_listening }
    end
    describe port('9091') do
      it { should_not be_listening }
    end
  end

  describe "configuring haproxy load balancing" do
    before :all do
      pp = <<-EOS
        $netcat = $::osfamily ? {
          'RedHat' => 'nc',
          'Debian' => 'netcat-openbsd',
        }
        package { $netcat: ensure => present, }
        package { 'screen': ensure => present, }
        if $::osfamily == 'RedHat' {
          service { 'iptables': ensure => stopped, }
        }
      EOS
      apply_manifest(pp, :catch_failures => true)

      ['5556','5557'].each do |port|
        shell(%{echo 'while :; do echo "HTTP/1.1 200 OK\r\n\r\nResponse on #{port}" | nc -l #{port} ; done' > /root/script-#{port}.sh})
        shell(%{/usr/bin/screen -dmS script-#{port} sh /root/script-#{port}.sh})
        sleep 1
        shell(%{netstat -tnl|grep ':#{port}'})
      end
    end

    describe "multiple ports" do
      it 'should be able to listen on an array of ports' do
        pp = <<-EOS
        class { 'haproxy': }
        haproxy::listen { 'stats':
          ipaddress => '127.0.0.1',
          ports     => ['9090','9091'],
          options   => {
            'mode'  => 'http',
            'stats' => ['uri /','auth puppet:puppet'],
          },
        }
        haproxy::listen { 'test00': ports => '80',}
        EOS
        apply_manifest(pp, :catch_failures => true)
      end

      it 'should have stats listening on each port' do
        ['9090','9091'].each do |port|
          shell("/usr/bin/curl -u puppet:puppet localhost:#{port}") do |r|
            r.stdout.should =~ /HAProxy/
            r.exit_code.should == 0
          end
        end
      end
    end
  end

  describe 'dependency requirements' do
    # C9712
    describe 'without concat' do
      before :all do shell("mv $(puppet apply --color=false -e 'notice(get_module_path(\"concat\"))'|grep concat|cut -d ' ' -f 3) /tmp") end
      after  :all do shell("mv /tmp/concat #{hosts.first[:distmoduledir]}") end
      it 'should fail' do
        apply_manifest(%{class { 'haproxy': }}, :expect_failures => true)
      end
    end
    # C9712
    describe 'without stdlib' do
      before :all do shell("mv $(puppet apply --color=false -e 'notice(get_module_path(\"stdlib\"))'|grep stdlib|cut -d ' ' -f 3) /tmp") end
      after  :all do shell("mv /tmp/stdlib #{hosts.first[:distmoduledir]}") end
      it 'should fail' do
        apply_manifest(%{class { 'haproxy': }}, :expect_failures => true)
      end
    end
  end

  # C9934
  describe "uninstalling haproxy" do
    it 'removes it' do
      pp = <<-EOS
        class { 'haproxy':
          package_ensure => 'absent',
          service_ensure => 'stopped',
        }
      EOS
      apply_manifest(pp, :catch_failures => true)
    end
    describe package('haproxy') do
      it { should_not be_installed }
    end
  end

  # C9935 C9939
  describe "disabling haproxy" do
    it 'stops the service' do
      pp = <<-EOS
        class { 'haproxy':
          service_ensure => 'stopped',
        }
      EOS
      apply_manifest(pp, :catch_failures => true)
    end
    describe service('haproxy') do
      it { should_not be_running }
      it { should_not be_enabled }
    end
  end
end
