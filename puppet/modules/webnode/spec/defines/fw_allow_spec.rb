require "spec_helper"

describe "webnode::fw_allow" do
  let(:title) { "port-8080" }
  let(:params) { { source: "172.28.0.0/16", port: 8080 } }
  let(:pre_condition) { "Exec { path => ['/usr/bin', '/bin'] } package { 'iptables': } exec { 'fw-default-drop': command => '/bin/true' }" }

  it { is_expected.to compile.with_all_deps }

  it "adds the rule for the source and port" do
    is_expected.to contain_exec("fw-allow-8080").with_command("iptables -A INPUT -s 172.28.0.0/16 -p tcp -m tcp --dport 8080 -j ACCEPT")
  end

  it "checks the rule first so a second run changes nothing" do
    is_expected.to contain_exec("fw-allow-8080").with_unless("iptables -C INPUT -s 172.28.0.0/16 -p tcp -m tcp --dport 8080 -j ACCEPT")
  end

  it "runs after iptables is installed and before the default drop" do
    is_expected.to contain_exec("fw-allow-8080").that_requires("Package[iptables]").that_comes_before("Exec[fw-default-drop]")
  end

  context "with a port outside 1 to 65535" do
    let(:params) { { source: "10.0.0.0/8", port: 70000 } }
    it { is_expected.to compile.and_raise_error(/expects an Integer\[1, 65535\]/) }
  end

  context "with an empty source" do
    let(:params) { { source: "", port: 80 } }
    it { is_expected.to compile.and_raise_error(/source/) }
  end
end
