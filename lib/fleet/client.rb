require 'fleet/connection'
require 'fleet/error'
require 'fleet/request'
require 'fleet/service_definition'
require 'fleet/client/machines'
require 'fleet/client/unit'
require 'fleet/client/state'

module Fleet
  class Client

    attr_accessor(*Configuration::VALID_OPTIONS_KEYS)

    def initialize(options={})
      options = Fleet.options.merge(options)
      Configuration::VALID_OPTIONS_KEYS.each do |key|
        send("#{key}=", options[key])
      end
    end

    include Fleet::Connection
    include Fleet::Request

    include Fleet::Client::Machines
    include Fleet::Client::Unit
    include Fleet::Client::State

    def list
      machines = list_machines['machines'] || []
      machine_ips = machines.each_with_object({}) do |machine, h|
        h[machine['id']] = machine['primaryIP']
      end

      states = list_states['states'] || []
      states.map do |service|
        {
          name: service['name'],
          load_state: service['systemdLoadState'],
          active_state: service['systemdActiveState'],
          sub_state: service['systemdSubState'],
          machine_id: service['machineID'],
          machine_ip: machine_ips[service['machineID']]
        }
      end
    end

    def submit(name, service_def)

      unless name =~ /\A[a-zA-Z0-9:_.@-]+\Z/
        raise ArgumentError, 'name may only contain [a-zA-Z0-9:_.@-]'
      end

      unless service_def.is_a?(ServiceDefinition)
        service_def = ServiceDefinition.new(service_def)
      end

      begin
        create_unit(name, service_def.to_unit(name))
      rescue Fleet::PreconditionFailed
      end
    end

    def load(name, service_def=nil)

      if service_def
        submit(name, service_def)
      end

      opts = { 'desiredState' => 'loaded', 'name' => name }
      update_unit(name, opts)
    end

    def start(name)
      opts = { 'desiredState' => 'launched', 'name' => name }
      update_unit(name, opts)
    end

    def stop(name)
      opts = { 'desiredState' => 'loaded', 'name' => name }
      update_unit(name, opts)
    end

    def unload(name)
      opts = { 'desiredState' => 'inactive', 'name' => name }
      update_unit(name, opts)
    end

    def destroy(name)
      delete_unit(name)
    end

    def status(name)
      get_unit(name)["currentState"].to_sym
    end

    def get_unit_state(name)
      options = { unitName: name }
      states = list_states(options)
      if states["states"]
        states["states"].first
      else
        fail NotFound, "Unit '#{name}' not found"
      end
    end

    protected

    def resource_path(resource, *parts)
      parts.unshift('fleet', fleet_api_version, resource).join('/')
    end
  end
end
