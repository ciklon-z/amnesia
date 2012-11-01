require 'libvirt'
require 'rexml/document'

class VM

  attr_reader :domain, :display, :ip, :ip6, :net, :remote_shell_port

  def initialize
    domain_xml = ENV['DOM_XML'] || Dir.pwd + "/cucumber/domains/default.xml"
    net_xml = ENV['NET_XML'] || Dir.pwd + "/cucumber/domains/default_net.xml"
    @read_domain_xml = File.read(domain_xml)
    @read_net_xml = File.read(net_xml)
    @parsed_domain_xml = REXML::Document.new(@read_domain_xml)
    @parsed_net_xml = REXML::Document.new(@read_net_xml)
    @iso = ENV['ISO'] || get_last_iso
    @virt = Libvirt::open("qemu:///system")
    setup_temp_domain
    @remote_shell_port = 1337
  end

  def clean_up_old
    domain_name = @parsed_domain_xml.elements['domain/name'].text
    begin
      old_domain = @virt.lookup_domain_by_name(domain_name)
    rescue Libvirt::RetrieveError
    else
      old_domain.destroy if old_domain.active?
      old_domain.undefine
    end
    net_name = @parsed_net_xml.elements['network/name'].text
    begin
      old_net = @virt.lookup_network_by_name(net_name)
    rescue Libvirt::RetrieveError
    else
      old_net.destroy if old_net.active?
      old_net.undefine
    end
  end

  def setup_temp_domain
    clean_up_old
    setup_network
    @domain = @virt.define_domain_xml(@read_domain_xml)
    add_iso_to_domain
  end

  def setup_network
    @net = @virt.define_network_xml(@read_net_xml)
    @net.create
    @ip = @parsed_net_xml.elements['network/ip/dhcp/host/'].attributes['ip']
    @parsed_net_xml.elements.each('network/ip') do |e|
      if e.attribute('family').to_s == "ipv6"
        @ip6 = e.attribute('address').to_s
      end
    end
  end

  def get_last_iso
    build_root_path = Pathname.new(Dir.pwd).parent
    Dir.chdir(build_root_path)
    iso_name = Dir.glob("*.iso").sort_by {|f| File.mtime(f)}.last
    build_root_path.to_s + "/" + iso_name
  end

  def add_iso_to_domain
    xml = <<EOF
    <disk>
      <source file="#{@iso}"/>
      <target dev='hdc' bus='ide'/>
    </disk>
EOF
    @domain.update_device(xml)
  end

  def is_running?
    @domain.active?
  end

  def execute(cmd, user = "amnesia")
    return VMCommand.new(self, cmd, user)
  end

  def start
    @domain.destroy if @domain.active?
    @domain.create
    @display = Display.new(@domain.name)
    @display.start
  end

  def stop
    @domain.destroy if @domain.active?
    @domain.undefine
    @net.destroy if @net.active?
    @net.undefine
    @display.stop
  end

  def take_screenshot(description)
    @display.take_screenshot(description)
  end

end
