require 'dhcp_common/server'
require 'smart_proxy_dhcp_infoblox/ip_address_arithmetic'

module Proxy::DHCP::Infoblox
  class Provider < ::Proxy::DHCP::Server
    include Proxy::Log
    include Proxy::Util
    include IpAddressArithmetic

    attr_reader :connection, :crud, :restart_grid, :unused_ips

    def initialize(connection, crud, restart_grid, unused_ips, managed_subnets)
      @connection = connection
      @crud = crud
      @restart_grid = restart_grid
      @unused_ips = unused_ips
      super('infoblox', managed_subnets, nil)
    end

    def find_subnet(address);::Proxy::DHCP::Subnet.new(address, '255.255.255.0'); end
    def load_subnets; end
    def load_subnet_data(_); end

    def subnets
      ::Infoblox::Network.all(connection).map do |network|
        address, prefix_length = network.network.split("/")
        netmask = cidr_to_ip_mask(prefix_length.to_i)
        managed_subnet?("#{address}/#{netmask}") ? Proxy::DHCP::Subnet.new(address, netmask, {}) : nil
      end.compact
    end

    def all_hosts(network_address)
      crud.all_hosts(full_network_address(network_address))
    end

    def all_leases(network_address)
      crud.all_leases(full_network_address(network_address))
    end

    def find_record(subnet_address, an_address)
      crud.find_record(full_network_address(subnet_address), an_address)
    end

    def add_record(options)
      crud.add_record(options)
      logger.debug("Added DHCP reservation for #{options[:ip]}/#{options[:mac]}")
      restart_grid.try_restart
    end

    def del_record(subnet, record)
      crud.del_record(full_network_address(subnet.network), record)
      logger.debug("Removed DHCP reservation for #{record.ip} => #{record}")
      restart_grid.try_restart
    end

    def unused_ip(subnet, _, from_ip_address, to_ip_address)
      unused_ips.unused_ip(subnet.network, from_ip_address, to_ip_address)
    end

    def find_network(network_address)
      network = ::Infoblox::Network.find(connection, 'network~' => network_address, '_max_results' => 1).first
      raise "Subnet #{network_address} not found" if network.nil?
      network
    end

    def full_network_address(network_address)
      find_network(network_address).network
    end
  end
end
