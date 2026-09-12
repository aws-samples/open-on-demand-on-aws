require "ood_core/refinements/hash_extensions"

module OodCore
  module BatchConnect
    class Factory
      using Refinements::HashExtensions

      # Build the DCV template from a configuration.
      # @param config [#to_h] the configuration for the batch connect template
      def self.build_dcv(config)
        context = config.to_h.symbolize_keys.reject { |k, _| k == :template }
        Templates::DCV.new(context)
      end
    end

    module Templates
      # A batch-connect template that starts an Amazon DCV (NICE DCV) virtual
      # session within a batch job and exposes it through Open OnDemand's reverse
      # proxy (/rnode/<host>/8443/). SSO is handled by the DCV simple external
      # authenticator: a one-time token is issued per session and passed to the
      # custom view.html.erb as the connection password (?authToken=...).
      #
      # ood_core ships no native DCV template, so this file must be installed into
      # the version-pinned ood_core batch_connect/templates dir and re-copied on
      # every OOD package upgrade (see install_ood.sh).
      class DCV < Template
        def initialize(context = {})
          super
        end

        private
          # Surface the DCV auth token (password) and session id to the custom
          # view so it can build the /rnode/<host>/8443/?authToken=...#<session> URL.
          # host + port come from the base conn_params.
          def conn_params
            (super + [:password, :dcv_session]).uniq
          end

          # Create the DCV session and issue its SSO token before the main script.
          def before_script
            <<-EOT.gsub(/^ {14}/, "")
              #{super}

              # DCV serves its web client on a fixed TLS port, not a random free port.
              port=8443

              # The session id is the batch-connect working-directory name.
              dcv_session="#{session_id}"

              echo "Creating DCV session ${dcv_session}..."
              dcv create-session --storage-root "${HOME}" "${dcv_session}"

              # Wait for the virtual X display to come up.
              display=""
              for i in $(seq 1 10); do
                display=$(dcv describe-session "${dcv_session}" 2>/dev/null | awk '/X display:/ {print $3}')
                [ -n "${display}" ] && break
                sleep 1
              done
              [ -n "${display}" ] || { echo "DCV session failed to start" >&2; clean_up 1; }

              # SSO: issue a one-time token via the DCV simple external
              # authenticator (must match auth-token-verifier in dcv.conf) and hand
              # it to the view as the connection password.
              password=$(create_passwd 32)
              echo "${password}" | dcvsimpleextauth add-user \\
                --user "$(whoami)" --session "${dcv_session}" \\
                --auth-dir /var/run/dcvsimpleextauth/ --append

              echo "DCV session ${dcv_session} ready on ${host}:${port} (display :${display})"
            EOT
          end

          # Run the main desktop script under the DCV session's display.
          # `dcv describe-session` reports the display already prefixed (e.g. ":0"),
          # so use it verbatim -- prefixing another ":" yields an invalid "::0".
          def run_script
            %(DISPLAY=${display} #{super})
          end

          # Close the DCV session on cleanup.
          def clean_script
            <<-EOT.gsub(/^ {14}/, "")
              #{super}

              dcv close-session "#{session_id}" 2>/dev/null || true
            EOT
          end

          # Session id = the working-directory basename (OOD-supplied per session).
          def session_id
            context.fetch(:work_dir).to_s.scan(%r{^.*/([^/]*)$})[0][0]
          end
      end
    end
  end
end
