#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
    apt-get update && apt-get install -y python3 python3-pip ruby
    pip3 install pytest packaging semver

    mkdir -p /home/user/rules

    cat << 'EOF' > /home/user/packages.json
{
  "auth_lib": "2.1.4",
  "parser_core": "1.5.0",
  "data_utils": "0.9.5"
}
EOF

    cat << 'EOF' > /home/user/rules/rule1.wafr
RULE "Auth_Bypass" {
    AFFECTS: "auth_lib"
    VULN_VERSIONS: ">= 2.0.0, <= 2.1.5"
}
EOF

    cat << 'EOF' > /home/user/rules/rule2.wafr
RULE "Parser_Crash" {
    AFFECTS: "parser_core"
    VULN_VERSIONS: "< 1.5.0"
}
EOF

    cat << 'EOF' > /home/user/rules/rule3.wafr
RULE "Data_Leak" {
    AFFECTS: "data_utils"
    VULN_VERSIONS: ">= 0.9.0, < 1.0.0"
}
EOF

    cat << 'EOF' > /home/user/legacy_parser.rb
require 'json'
require 'rubygems'

def parse_wafr(filepath)
  content = File.read(filepath)
  state = :IDLE
  rule_name = nil
  affects = nil
  versions = nil

  content.each_line do |line|
    line = line.strip
    case state
    when :IDLE
      if line =~ /^RULE\s+"([^"]+)"\s*\{/
        rule_name = $1
        state = :IN_BLOCK
      end
    when :IN_BLOCK
      if line =~ /^AFFECTS:\s+"([^"]+)"/
        affects = $1
      elsif line =~ /^VULN_VERSIONS:\s+"([^"]+)"/
        versions = $1
      elsif line == "}"
        state = :DONE
      end
    end
  end

  return nil unless state == :DONE
  { name: rule_name, affects: affects, versions: versions }
end

# In Ruby, we used Gem::Version for semver comparison
def check_vuln(installed_version, vuln_condition_string)
  conditions = vuln_condition_string.split(',').map(&:strip)
  installed = Gem::Version.new(installed_version)

  conditions.all? do |cond|
    op, ver = cond.split(' ')
    target = Gem::Version.new(ver)
    case op
    when '>=' then installed >= target
    when '<=' then installed <= target
    when '>' then installed > target
    when '<' then installed < target
    when '==' then installed == target
    else false
    end
  end
end
EOF

    useradd -m -s /bin/bash user || true
    chmod -R 777 /home/user
