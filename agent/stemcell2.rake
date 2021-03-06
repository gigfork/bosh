# Copyright (c) 2009-2012 VMware, Inc.

require File.join(File.dirname(__FILE__), "/lib/agent/version.rb")
require "rbconfig"

namespace :stemcell2 do

  desc "Build stemcell"
  task :basic, :infrastructure do |t, args|
    options = default_options(args)
    options[:stemcell_name] ||= "bosh-stemcell"
    options[:stemcell_version] ||= Bosh::Agent::VERSION
    options[:image_create_disk_size] = 1380

    options = options.merge(bosh_agent_options)

    build("stemcell-#{args[:infrastructure]}", options)
  end

  desc "Build micro bosh stemcell"
  task :micro, :infrastructure, :manifest, :tarball do |t, args|
    options = default_options(args)
    options[:stemcell_name] ||= "micro-bosh-stemcell"
    options[:stemcell_version] ||= Bosh::Agent::VERSION
    options[:image_create_disk_size] = 2048

    options = options.merge(bosh_agent_options)
    options = options.merge(bosh_micro_options(args))

    build("stemcell-#{args[:infrastructure]}", options)
  end

  desc "Build Micro Cloud Foundry"
  task :mcf, :infrastructure, :manifest, :tarball do |t, args|
    options = default_options(args)
    options[:stemcell_name] ||= "mcf-stemcell"
    options[:stemcell_version] ||= Bosh::Agent::VERSION
    options[:image_create_disk_size] = 16384
    options[:build_time] = ENV['BUILD_TIME'] ||
      Time.now.strftime('%Y%m%d.%H%M%S')
    options[:version] = ENV['MCF_VERSION'] || "9.9.9_#{options[:build_time]}"
    options[:bosh_users_password] = 'micr0cloud'

    options = options.merge(bosh_agent_options)
    options = options.merge(bosh_micro_options(args))

    build("stemcell-mcf", options)
  end

  def default_options(args)
    infrastructure = args[:infrastructure]
    unless infrastructure
      STDERR.puts "Please specify target infrastructure (vsphere, aws, openstack)"
      exit 1
    end

    options = {
      :system_parameters_infrastructure => infrastructure,
      :stemcell_name => ENV["STEMCELL_NAME"],
      :stemcell_version => ENV["STEMCELL_VERSION"],
      :stemcell_infrastructure => infrastructure,
      :stemcell_hypervisor => get_hypervisor(infrastructure),
      :bosh_protocol_version => Bosh::Agent::BOSH_PROTOCOL,
      :UBUNTU_ISO => ENV["UBUNTU_ISO"],
      :UBUNTU_MIRROR => ENV["UBUNTU_MIRROR"],
      :ruby_bin => ENV["RUBY_BIN"] || File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name']),
    }

    # Pass OVFTOOL environment variable when targeting vsphere
    if infrastructure == "vsphere"
      options[:image_vsphere_ovf_ovftool_path] = ENV["OVFTOOL"]
    end

    options
  end

  def bosh_agent_options
    {
      :bosh_agent_src_dir => File.expand_path("..", __FILE__)
    }
  end

  def bosh_micro_options(args)
    {
      :bosh_micro_enabled => "yes",
      :bosh_micro_package_compiler_path => File.expand_path("../../package_compiler", __FILE__),
      :bosh_micro_manifest_yml_path => args[:manifest],
      :bosh_micro_release_tgz_path => args[:tarball],
    }
  end

  def get_working_dir
    "/var/tmp/bosh/agent-#{version}-#{$$}"
  end

  def get_hypervisor(infrastructure)
    return ENV["STEMCELL_HYPERVISOR"] if ENV["STEMCELL_HYPERVISOR"]

    case infrastructure
      when "vsphere"
        hypervisor = "esxi"
      when "aws"
        hypervisor = "xen"
      when "openstack"
        hypervisor = "kvm"
      else
        raise "Unknown infrastructure: #{infrastructure}"
    end
    hypervisor
  end

  def env
    keep = %w{
      HTTP_PROXY
      http_proxy
      NO_PROXY
      no_proxy
      }

    format_env(ENV.select { |k| keep.include?(k) })
  end

  # Format a hash as an env command.
  def format_env(h)
    'env ' + h.map { |k,v| "#{k}='#{v}'" }.join(' ')
  end

  def build(spec, options)
    root = get_working_dir
    mkdir_p root

    build_path = File.join(root, "build")
    cp_r File.expand_path("../misc/stemcell/build2", __FILE__), build_path, :preserve => true

    work_path = File.join(root, "work")
    mkdir_p work_path

    # Apply options
    settings_path = File.join(build_path, "etc", "settings.bash")
    File.open(settings_path, "a") do |f|
      f.print "\n# %s\n\n" % ["=" * 20]
      options.each do |k, v|
        f.print "#{k}=#{v}\n"
      end
    end

    builder_path = File.join(build_path, "bin", "build_from_spec.sh")
    spec_path = File.join(build_path, "spec", "#{spec}.spec")

    # Run builder
    STDOUT.puts "building in #{work_path}..."
    system("sudo #{env} #{builder_path} #{work_path} #{spec_path} #{settings_path}")
  end
end
