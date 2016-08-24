%% Copyright (c) 2012 Campanja AB
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% A copy of the license is included in the file LICENSE.
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%%% periodically dump reports of folsom metrics to graphite
-module(folsomite_server).
-behaviour(gen_server).

%% management api
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         code_change/3, terminate/2]).


-define(APP, folsomite).
-define(TIMER_MSG, '#flush').

-record(state, {flush_interval :: integer(),
                node_key       :: string(),
                node_prefix    :: string(),
                metric_prefix  :: string(),
                timer_ref      :: reference()}).


%% management api
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, no_arg, []).

%% gen_server callbacks
init(no_arg) ->
    process_flag(trap_exit, true),
    FlushInterval = get_env(flush_interval),
    Ref = erlang:start_timer(FlushInterval, self(), ?TIMER_MSG),
    MetricPrefix = case application:get_env(?APP, metric_prefix, "") of
                       "" ->
                           "";
                       Else when is_list(Else) ->
                           Else ++ "."
                   end,
    State = #state{flush_interval = FlushInterval,
                   node_key = node_key(),
                   node_prefix = node_prefix(),
                   metric_prefix = MetricPrefix,
                   timer_ref = Ref},
    {ok, State}.

handle_call(Call, _, State) ->
    unexpected(call, Call),
    {noreply, State}.

handle_cast(Cast, State) ->
    unexpected(cast, Cast),
    {noreply, State}.

handle_info({timeout, _R, ?TIMER_MSG},
            #state{timer_ref = _R, flush_interval = FlushInterval} = State) ->
    Ref = erlang:start_timer(FlushInterval, self(), ?TIMER_MSG),
    F = fun() -> send_stats(State) end,
    folsom_metrics:histogram_timed_update({?APP, send_stats}, F),
    {noreply, State#state{timer_ref = Ref}};
handle_info({'EXIT', _, _} = Exit, State) ->
    {stop, {exit, Exit}, State};
handle_info(Info, State) ->
    unexpected(info, Info),
    {noreply, State}.

terminate(shutdown, #state{timer_ref = Ref}) ->
    erlang:cancel_timer(Ref),
    ok;

terminate(_, _) -> ok.

code_change(_, State, _) -> {ok, State}.


%% internal
get_stats() ->
    Memory = expand0(folsom_vm_metrics:get_memory(), [memory, vm]),
    Stats = expand0(folsom_vm_metrics:get_statistics(), [vm]),
    Info = expand0(get_system_info(), [system_info, vm]),
    Metrics = folsom_metrics:get_metrics_info(),
    Memory ++ Stats ++ Info ++ lists:flatmap(fun expand_metric/1, Metrics).


expand_metric({Name, Opts}) ->
    case proplists:get_value(type, Opts) of
            undefined -> [];
            histogram ->
                Stats = folsom_metrics:get_histogram_statistics(Name),
                M = proplists:delete(histogram, Stats),
                expand0(M, [Name]);
            Type ->
                case lists:member(Type,
                                  [counter, gauge, meter, spiral, meter_reader]) of
                    true ->
                        M = folsom_metrics:get_metric_value(Name),
                        expand0(M, [Name]);
                    false -> []
                end
        end;
expand_metric(_) ->
    [].

expand0(M, NamePrefix) -> lists:flatten(expand(M, NamePrefix)).

expand({K, X}, NamePrefix) ->
    expand(X, [K | NamePrefix]);
expand([_|_] = Xs, NamePrefix) ->
    [expand(X, NamePrefix) || X <- Xs];
expand(X, NamePrefix) ->
    K = string:join(lists:map(fun a2l/1, lists:reverse(NamePrefix)), " "),
    [{K, X}].

send_stats(State) ->
    Metrics = get_stats(),
    Timestamp = num2str(unixtime()),
    Message = [format1(State#state.metric_prefix, State#state.node_key, M, Timestamp) || M <- Metrics],
    case folsomite_graphite_client_sup:get_client() of
        {ok, Socket} -> folsomite_graphite_client:send(Socket, Message);
        {error, _} = Error -> Error
    end.

format1(Prefix, Base, {K, V}, Timestamp) ->
    [Prefix, "folsomite.", Base, ".", space2dot(K), " ", a2l(V), " ", Timestamp, "\n"].

num2str(NN) -> lists:flatten(io_lib:format("~w",[NN])).
unixtime()  -> {Meg, S, _} = os:timestamp(), Meg*1000000 + S.


node_prefix() ->
    NodeList = atom_to_list(node()),
    [A, _] = string:tokens(NodeList, "@"),
    A.

node_key() ->
    case application:get_env(?APP, node_key) of
        undefined ->
            NodeList = atom_to_list(node()),
            Opts = [global, {return, list}],
            NodeList1 = re:replace(NodeList, "[\.]", "_", Opts),
            re:replace(NodeList1, "[\@]", ".", Opts);
        {ok, NodeKey} when is_list(NodeKey) ->
            NodeKey
    end.

a2l(X) when is_list(X) -> X;
a2l(X) when is_binary(X) -> binary_to_list(X);
a2l(X) when is_atom(X) -> atom_to_list(X);
a2l(X) when is_integer(X) -> integer_to_list(X);
a2l(X) when is_float(X) -> float_to_list(X);
a2l(X) when is_tuple(X) -> string:join([a2l(A) || A <- tuple_to_list(X)], " ").

space2dot(X) -> string:join(string:tokens(X, " "), ".").

get_env(Name) ->
    get_env(Name, undefined).

get_env(Name, Default) ->
    case application:get_env(?APP, Name) of
        {ok, Value} ->
            Value;
        undefined ->
            Default
    end.

unexpected(Type, Message) ->
    error_logger:info_msg(" unexpected ~p ~p~n", [Type, Message]).

get_system_info() ->
    L = folsom_vm_metrics:get_system_info(),
    [{K, V} || {K, V} <- L,
               lists:member(K, [port_count, process_count])].
