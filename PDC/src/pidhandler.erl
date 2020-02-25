%% @author BlackBase
%% @doc @todo Add description to pidhandler.


-module(pidhandler).

-export([handler/2]).

-include("types.hrl").

handler(PidHandlerList,Conf=#config{})->
	log_register({log,"##PIDDB Process##","",stdout}),
	receive
		{insert,PidList}->
			log_register({log,"Insert Into Ram : ",PidList,stdout}),
			
			% For Saving In List Please Per Connection Make Tupel That Contains Pid Element %
			TMPList=lists:append(PidHandlerList, [list_to_tuple(PidList)]),
			
			handler(TMPList,Conf);
		
		{delete,Pid,PPid}->
			% I Found Element And Kill All Process Linked To This Process %
			% Before These Code Our Process Surly Closed : Couse link %
			
			log_register({log,"Close Process Started : ",PidHandlerList,stdout}),
			
			case for(PidHandlerList,0,PidHandlerList,Pid,fun(List,PidHL)-> kill(List),
												 NPidHL=lists:delete(list_to_tuple(List), PidHL),
													   NPidHL % Full Result Return For Killing %
						 end) of
				{phlist,TMPList}->
					log_register({log,"List After Close Process : ",TMPList,stdout}),
					handler(TMPList,Conf);
				{none,_}->
					handler(PidHandlerList,Conf)
			end;
		
		{get,Pid,SelfPid}-> % I do not do functionality test %
			log_register({log,"Show Handler List : ",PidHandlerList,stdout}),

			SelfPid ! for(PidHandlerList,0,PidHandlerList,Pid,0),
			
			handler(PidHandlerList,Conf);
		
		{fullget,SelfPid}->
			SelfPid ! {pidlist,PidHandlerList},
			
			handler(PidHandlerList,Conf);
		
		_->
			log_register({log,"Wrong Msg RamHandler",{},stdout}),
			handler(PidHandlerList,Conf)
	end.

for([],FullList,PidHandlerList,Elem,VoidCall)-> {none,[]};
for([H|T],FullList,PidHandlerList,Elem,VoidCall)->
	log_register({log,"Element : ",H,stdout}),
	
	if is_tuple(H) ->
		case for(tuple_to_list(H),tuple_to_list(H),PidHandlerList,Elem,VoidCall) of
			{list,FList}->
				{list,FList}; % Return Full PH In Ram That Surly Change In VoidCall %
			{phlist,PHList}->
				{phlist,PHList}; % Return Just List That Finded %
			_->
				for(T,0,PidHandlerList,Elem,VoidCall)
		end;
	true ->
		if H == Elem ->
				  log_register({log,"I Found Element : ",H,stdout}),
				  
				  %Send Full List For To Handler Or return it%
				  if is_function(VoidCall) ->
						Res=VoidCall(FullList,PidHandlerList),
						{phlist,Res};
				  true->
				  		{list,FullList} % Just Return List That Found
				  end;
				  
		true ->
				for(T,FullList,PidHandlerList,Elem,VoidCall)
		end
	end.

% Utility %

kill([])-> ok;
kill([H|T])->
	IPA=is_process_alive(H),
	
	if IPA == true ->
		log_register({log,"This Process Is Alive So Killing Pid : ",H,stdout}),
		H ! {close},
		kill(T);
	true ->
		log_register({log,"This Process Is Not Alive So Killing Pid Did Not Send : ",H,stdout}),
		kill(T)
	end.

log_register(Struct)->
	Pid=erlang:whereis(wrouteL),
	Pid ! Struct.
