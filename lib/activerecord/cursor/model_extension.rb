require 'activerecord/cursor/params'

module ActiveRecord
  module Cursor
    module ModelExtension
      extend ActiveSupport::Concern

      module ClassMethods
        def cursor(options = {})
          Thread[:options] = default_options.merge!(options).symbolize_keys!
          Thread[:options][:direction] =
            if Thread[:options].key?(:start) || Thread[:options].key?(:stop)
              Thread[:options].key?(:start) ? :start : :stop
            end
          Thread[:cursor] = Params.decode(Thread[:options][Thread[:options][:direction]]).value
          Thread[:records] = on_cursor.in_order.limit(Thread[:options][:size] + 1)
          set_cursor
          Thread[:records]
        rescue ActiveRecord::StatementInvalid
          raise Cursor::InvalidCursor
        end

        def next_cursor
          Thread[:next]
        end

        def prev_cursor
          Thread[:prev]
        end

        def on_cursor
          if Thread[:cursor].nil?
            where(nil)
          else
            where(
              "(#{column} = ? AND #{table_name}.id #{sign_of_inequality} ?) OR (#{column} #{sign_of_inequality} ?)",
              Thread[:cursor][:key],
              Thread[:cursor][:id],
              Thread[:cursor][:key]
            )
          end
        end

        def in_order
          order("#{column} #{by}", "#{table_name}.id #{by}")
        end

        private

        def default_options
          { key: 'id', reverse: false, size: 1 }
        end

        def column
          "#{table_name}.#{Thread[:options][:key]}"
        end

        def sign_of_inequality
          case Thread[:options][:reverse]
          when true
            Thread[:options][:direction] == :start ? '<' : '>'
          when false
            Thread[:options][:direction] == :start ? '>' : '<'
          end
        end

        def by
          direction = Thread[:options][:direction]
          case Thread[:options][:reverse]
          when true
            direction == :start || direction.nil? ? 'desc' : 'asc'
          when false
            direction == :start || direction.nil? ? 'asc' : 'desc'
          end
        end

        def set_cursor
          Thread[:next] = nil
          Thread[:prev] = nil
          if Thread[:options][:direction] == :start
            set_cursor_on_start
          elsif Thread[:options][:direction] == :stop
            set_cursor_on_stop
          elsif Thread[:records].size == Thread[:options][:size] + 1
            Thread[:records] = Thread[:records].limit(Thread[:options][:size])
            Thread[:next] = generate_cursor(Thread[:records][Thread[:records].size - 1])
          end
        end

        def set_cursor_on_start
          record = Thread[:records][0]
          Thread[:prev] = generate_cursor(record) if record
          size = Thread[:records].size
          Thread[:records] = Thread[:records].limit(Thread[:options][:size])
          return unless size == Thread[:options][:size] + 1

          Thread[:next] = generate_cursor(Thread[:records][Thread[:records].size - 1])
        end

        def set_cursor_on_stop
          record = Thread[:records][0]
          Thread[:next] = generate_cursor(record) if record
          size = Thread[:records].size
          reverse_by = by == 'asc' ? 'desc' : 'asc'
          Thread[:records] = Thread[:records].reorder("#{column} #{reverse_by}").limit(Thread[:options][:size])
          return unless size == Thread[:options][:size] + 1

          Thread[:prev] = generate_cursor(record)
        end

        def generate_cursor(record)
          Params.new(id: record.id, key: record.public_send(Thread[:options][:key])).encoded
        end
      end
    end
  end
end
