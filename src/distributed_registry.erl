-module(distributed_registry).

-export([
  register_name/2,unregister_name/1, whereis_name/1, send/2
]).

-define(DISTRIBUTED_REGISTRY, 'Elixir.DistributedRegistry').


%% @doc Registers a name to a pid. Should not be used directly,
%% should only be used with `{via, swarm, Name}`
-spec register_name(term(), pid()) -> yes | no.
register_name(Name, Pid) ->
    ?DISTRIBUTED_REGISTRY:register_name(Name, Pid).

%% @doc Unregisters a name.
-spec unregister_name(term()) -> ok.
unregister_name(Name) ->
    ?DISTRIBUTED_REGISTRY:unregister_name(Name).

%% @doc Get the pid of a registered name.
-spec whereis_name(term()) -> pid() | undefined.
whereis_name(Name) ->
    ?DISTRIBUTED_REGISTRY:whereis_name(Name).

%
%% @doc This function sends a message to the process registered to the given name.
%% It is intended to be used by GenServer when using `GenServer.cast/2`, but you
%% may use it to send any message to the desired process.
%% @end
-spec send(term(), term()) -> ok.
 send(Name, Msg) ->
    ?DISTRIBUTED_REGISTRY:send(Name, Msg).