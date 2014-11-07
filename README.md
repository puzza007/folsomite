### Folsomite

[Folsom][1] is an Erlang based metrics system inspired by Coda Hale's
metrics (https://github.com/codahale/metrics/).

[Graphite][2] is a realtime graphing system.

Folsomite runs in your Erlang virtual machine, periodically aggregates
all present Folsom metrics and forwards them to your Graphite server.

The canonical location for the source code is [on github][3]. The
software is copyrighted 2012 [Campanja AB][4] and distributed under
the [Apache License, Version 2.0][5].


Comments and patches always welcome!

[1]: https://github.com/boundary/folsom
[2]: http://graphite.wikidot.com/
[3]: https://github.com/campanja/folsomite/
[4]: http://www.campanja.com/
[5]: http://www.apache.org/licenses/LICENSE-2.0.html


#### Building and running

Any version of erlang suitable to run Folsom should be supported. Use
rebar to build like:

    ./rebar get-deps compile

You can start it from the shell:

    $ erl -pa ebin deps/*/ebin -s folsomite

#### Example config

    %% -*-erlang-*-
    {application, my_app,
     [{description, "my_app"},
      {vsn, git},
      {registered, []},
      {applications, [kernel,
                      stdlib,
                      folsomite]},
      {mod, []},
      {env,
       [{folsom, [{counter, [{my_app, my_counter}, {my_app, my_counter2}]},
                  {gauge, [my_gauge]},
                  {histogram, [{my_app, my_histo}, slide_uniform, {60, 1028}]}
                 ]}
        {folsomite,
         [{graphite_host, "graphite.example.com"},
          {node_key, "billing-prod-us-east-1"}
         ]}
       ]}
     ]}.

(the histogram example above needs https://github.com/boundary/folsom/pull/31).
