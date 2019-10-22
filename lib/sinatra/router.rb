module Sinatra
  # Router class to avoid use of ALL middleware
  class Router
    def initialize(app = nil, *_args, &block)
      @app        = app
      @apps       = []
      @conditions = []
      @run        = nil

      instance_eval(&block) if block
      @routes = build_routing_table
    end

    def call(env)
      ret = try_route(env['REQUEST_METHOD'], env['PATH_INFO'], env)
      return ret unless ret.nil?

      call_default_app(env)
    end

    # specify the default app to run if no other app routes matched
    def run(app)
      raise '@run already set' if @run
      @run = app
    end

    def mount(app, *conditions)
      # mix in context based conditions with conditions given by parameter
      @apps << [app, @conditions + conditions]
    end

    # yield to a builder block in which all defined apps will only respond for
    # the given version
    def version(version, &block)
      @conditions = { version: version }
      instance_eval(&block) if block
      @conditions = {}
    end

    protected

    def with_conditions(*args, &block)
      old = @conditions
      @conditions += args
      instance_eval(&block) if block
      @conditions = old
    end

    private

    def call_default_app(env)
      raise usage_string unless default_app

      default_app.call(env)
    end

    def default_app
      @app || @run
    end

    def usage_string
      'router needs to be mounted as middleware or contain a run statement'
    end

    def build_routing_table
      apps_with_routes.each_with_object({}) do |app_cond, all_routes|
        app, conditions = app_cond
        app.routes.each do |verb, routes|
          all_routes[verb] ||= []
          all_routes[verb] += routes.map do |pattern, _, _, _|
            [pattern, conditions, app]
          end
        end
      end
    end

    def apps_with_routes
      @apps.select { |app, _conds| app.respond_to?(:routes) }
    end

    def try_route(verb, path, env)
      # see Sinatra's `route!`
      return unless @routes[verb].is_a?(Array)

      @routes[verb].each do |pattern, conditions, app|
        next unless pattern.match(path)
        next unless conditions.all? { |condition| condition.call(env) }

        status, headers, response = app.call(env)
        # if we got a pass, keep trying routes
        next if headers['X-Cascade'] == 'pass'

        return status, headers, response
      end

      nil
    end
  end
end
