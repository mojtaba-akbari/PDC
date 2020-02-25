%% @author BlackBase
%% @doc @todo Add description to wroute.


-module(wroute).

-export([init/0,main/0,l_event_recv/6,l_event_send/3,c_event_send/5,c_event_recv/6,event_listen/4,init_connect/3,init_server/2]).

-include("types.hrl").

init()->
	PMain=spawn(?MODULE,main,[]),
	register(wrouteM,PMain).

main()->
	% Test Enviroment %
	
	
	%% Initialize Sys %%

	
	%% Read Config File %%
	{FL,Conf}=confighandler:init("/etc/wroute.cfg"),
	
	PidLog=spawn(loghandler,init,[{Conf#config.capturefile,Conf#config.logfile,Conf#config.capture,Conf#config.logging},FL,self()]),
	register(wrouteL,PidLog),
	
	%% Initialize Record Per Set %%
	
	PidHandler=[],
	HARepo=[],
	IsolateRepo=[],
	
	%% Initialize InRam List %%
	PidHInRam=spawn(pidhandler,handler,[PidHandler,Conf]),
	
	%% We Should Start TCP Server For Start %%
	init_fserver(FL, Conf),
	
	% Centeral Msg Process %
	base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf).

% Centeral Msg Process %
base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf=#config{}) ->
	receive
		{make_proxy,Sock,DR}->
			
			log_register({log,"Making Proxy : ",DR,stdout}),
			
			% Before Any Action First Check Isolate Repo %
			IsIso=find_isoitem(IsolateRepo,DR),
			if IsIso == true ->
				   log_register({log,"This DR Is Isolated : ",DR,stdout}),
				   % Return %
				   base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf);
			true->
				UnIso=true
			end,

			LPidS=spawn(?MODULE,l_event_send,[self(),Sock,Conf]),
			
			% First Element Is Master Sender And After that Master Receive %
			% Duplicate Sender %
			% If State Was True So Should Change HA Action HA Is Unique Per Port In Server%

			Item=find_haitem(HARepo, DR),
			
			log_register({log,"HA Item Suggestion : ",Item,stdout}),
			
			ListPid=init_connect(Item,LPidS,Conf),
			
			% Destructive Part (We Have Some Loos Data Here) %
			if ListPid == destructive ->
				   LPidS ! {close};
			true->
				LPidR=spawn(?MODULE,l_event_recv,[self(),ListPid,LPidS,Sock,DR#peer.replica,Conf]),
			
				% Format Of List : LPidS,LPidR,CPidS,CPidR,[...DuplicateS...] %
				PidHInRam ! {insert,[LPidS]++[LPidR]++ListPid}
			end,

			base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf);

		{close_proxy,PidS,Sock}->
			
			log_register({log,"Close Process And Proxy : ",{PidS,Sock},stdout}),
			
			% Close Socket Very Fast %
			gen_tcp:close(Sock),

			PidHInRam ! {delete,PidS,self()},
			
			base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf);
		
		{changeHA,UPDR}->
			
			% DR Updated Now Change %
			log_register({log,"Chage HA....",UPDR,stdout}),
			base(PidHandler,PidHInRam,HARepo++[{true,UPDR}],IsolateRepo,Conf);
		
		{isolate,SSig,DR}->
			
			% DR Isolate And Do Not Accept Any Socket %
			log_register({log,"Isolate Starting In (DR)....",DR,stdout}),
			base(PidHandler,PidHInRam,HARepo,IsolateRepo++[DR],Conf);
		
		{isolate,PORT}->
			% DR Isolate With Port %
			log_register({log,"Isolate Starting In (Port)....",PORT,stdout}),
			DR=#peer{p1="NULLDR",p1port=PORT,p2="",p2port=PORT,master=0,last=0,alive=0,replica=0,duplicates=[]},
			
			base(PidHandler,PidHInRam,HARepo,IsolateRepo++[DR],Conf);
			
		{unisolate,SSig,DR}->
			% DR Unisolate And Accept Any Socket %
			log_register({log,"UnIsolate Starting In....",DR,stdout}),
			IsoTMP=lists:delete(DR, IsolateRepo),
			
			base(PidHandler,PidHInRam,HARepo,IsoTMP,Conf);
		
		{unisolate,PORT}->
			% DR Unisolate And Accept Any Socket %
			log_register({log,"UnIsolate Starting In (Port)....",PORT,stdout}),
			DR=#peer{p1="NULLDR",p1port=PORT,p2="",p2port=PORT,master=0,last=0,alive=0,replica=0,duplicates=[]},
			IsoTMP=lists:delete(DR, IsolateRepo),
			
			base(PidHandler,PidHInRam,HARepo,IsoTMP,Conf);
		
		{fulldestroy,DRA}->
			log_register({log,"****Full Destroy For DR****",DRA,stdout}),
			
			base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf);
		
		{pidlist,List}->
			log_register({log,"Pid List Contains : ",List,stdout}),
			
			base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf);
		
		{process}->
			
			ListPid=erlang:processes(),
			log_register({log,"Process : ",ListPid,stdout}),
			
			base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf);
		
		{reload}->
			% Dose Not Implement %
			
			base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf);

		{stop} ->
			
			% Dose Not Implement %
			base(PidHandler,PidHInRam,HARepo,IsolateRepo,Conf)
	end.

% Proxy Server %
init_fserver([],Conf=#config{})-> ok;
init_fserver([H|T],Conf=#config{})->
	init_server(H,Conf),
	init_fserver(T,Conf).

init_server(DR=#peer{},Conf=#config{})->
	log_register({log,"Starting Listening On Ports : ",DR#peer.p1port,stdout}),
	% Listening %
	{ok,LSock}=gen_tcp:listen(DR#peer.p1port, [binary,{packet,0},{active,false}]),
	PidListener=spawn(?MODULE,event_listen,[self(),LSock,DR,Conf]),
	% Need Save These Pids :) Not Impelement%

	% Per Listerner We Need Run One HA Parameter %
	PidHA=spawn(hahandler,handler,[self(),DR,Conf]),
	register(list_to_atom("HA"++integer_to_list(DR#peer.p1port)),PidHA).

event_listen(PPid,LSock,DR,Conf=#config{})->
	log_register({log,"Listen : ",DR,stdout}),
	
	{ok,Sock}=gen_tcp:accept(LSock),
	
	log_register({log,"I Accept Remote Host To : ",Sock,stdout}),
	log_register({log,"Signal To Base (make proxy) : ",{make_proxy,Sock,DR},stdout}),
	
	
	PPid ! {make_proxy,Sock,DR},
	
	event_listen(PPid,LSock,DR,Conf).

% Connection Listener Action %
l_event_recv(PPid,ListPidS,LPidS,Sock,IsReplica,Conf=#config{})->
	% Link Two Process For Better Handling Pair Process %
	
	case gen_tcp:recv(Sock, 0) of
		{ok,B} ->
			
			% For Mainplute Data %
			log_register({log,"Data : ",B,stdout}),
			
			% Delete Pid That Is In Even Position Because N duplicate Should Have S,R Point %
			log_register({log,"I Should Send Data To Even Item Of This List : ",ListPidS,stdout}),
			
			% If Replica Was Disabled So Just Send To Master Item=1 Or If Replica Was Enabled Send Data To Item Odd %
			if IsReplica == 1 ->
				send_struct_Predictlist(ListPidS,{send,B},1,fun(Item)-> if (Item rem 2) == 0 -> 
																		   false; 
																	   true ->
																		   true
																	   end
																	end);
			true->
				send_struct_Predictlist(ListPidS,{send,B},1,fun(Item)-> if Item == 1 -> 
																		   true; 
																	   true ->
																		   false
																	   end
																	end)
			end,
			

			l_event_recv(PPid,ListPidS,LPidS,Sock,IsReplica,Conf);
		
		{error,closed} ->
			log_register({log,"Destroyed Receiver recv: ",self(),stdout}),
			PPid ! {close_proxy,LPidS,Sock},
			exit("Natural");
		_->
			log_register({log,"Destroyed Receiver _: ",self(),stdout}),
			PPid ! {close_proxy,LPidS,Sock},
			exit("Natural")
	end,
	receive 
		{close} ->
			log_register({log,"Destroyed Receiver event: ",self(),stdout}),
			exit("Natural")
	end.

l_event_send(PPid,Sock,Conf=#config{})->
	receive 
		{send,Data} ->
			case gen_tcp:send(Sock, Data) of
				ok->
					l_event_send(PPid,Sock,Conf);
				_->
					log_register({log,"Client Down? LSocket Closed","",stdout}),
					PPid ! {close_proxy,self(),Sock},
					exit("CSocket Closed")
			end;
		{close} ->
			log_register({log,"Destroyed Sender : ",self(),stdout}),
			exit("Natural")
	end.


%% Connection Generator %%
%% We Should Create All Master And Duplicate Peer %%
init_connect(DR,LPidS,Conf=#config{})->
	% Check Alive Duplicate Should Insurance Capture Data (We Capture Data Just In Master Node) %
	% We Should Capture Data Just By Master We Have Just One File Per Port %
	% Find Replica That Need Capture Data And Now Is Off %
	
	% In Socket We Can Find Master If Down %
	Sock = case gen_tcp:connect(DR#peer.p2, DR#peer.p2port, [binary,{active,false},{packet,0}]) of
					{ok,Sc}->
						Sc;
			   		{error,Reason}->
						
						log_register({log,"CSocket Error : ",Reason,stdout}),
						ha_register({emergency,DR}, "HA"++integer_to_list(DR#peer.p1port)),
						% Master Down Return Destructive %
						destructive
		   end,
	
	if Sock /= destructive ->
		ADeadList = find_deaditem(DR#peer.duplicates,[]),
		
		TPidS=spawn(?MODULE,c_event_send,[self(),ADeadList,Sock,DR,Conf]),
		TPidR=spawn(?MODULE,c_event_recv,[self(),[LPidS],TPidS,DR#peer.master,Sock,Conf]),
		
		
		% Return Format is MasterS,MasterR + (Duplicate) *** If Replica Set Was Disable So We Should Not Make Replica Set For Sending Data *** %
		if DR#peer.replica == 1->
			[TPidS,TPidR]++init_duplicate(DR#peer.duplicates,LPidS,[],DR,Conf);
		true->
			[TPidS,TPidR]
		end;
	   
	true->
		destructive
	end.

init_duplicate([],LPidS,PidList,DR,Conf=#config{})-> PidList;
init_duplicate([H|T],LPidS,PidList,DR,Conf=#config{})->
	log_register({log,"Make Connection To Duplicates : ",H,stdout}),
	
	% If In List We Have Dead Server So We Should Capture Data %
	if H#peer.alive == 1 ->
		{ok,Sock} = gen_tcp:connect(H#peer.p2, H#peer.p2port, [binary,{active,false},{packet,0}]),

		TPidS=spawn(?MODULE,c_event_send,[self(),[],Sock,DR,Conf]),
	
		% Receive Can Disabled By MicroProcessor %
		% But Get Data For Logging From Duplicate %
		TPidR=spawn(?MODULE,c_event_recv,[self(),[LPidS],TPidS,0,Sock,Conf]),
	
		init_duplicate(T,LPidS,PidList++[TPidS]++[TPidR],DR,Conf);
	true->
		init_duplicate(T,LPidS,PidList,DR,Conf)
	end.

c_event_send(PPid,CaptureList,Sock,DR,Conf=#config{})->
	receive
		{send,Data} ->
			% Capture Data %
			% Capture List= DeadItem %
			if (CaptureList /= []) and (DR#peer.replica == 1)->
				   
				log_register({log,"I Should Copy Data","",stdout}),
				
				% Before Sending, Writing It In File %
				log_register({data,Data,file,CaptureList}),
				
				case gen_tcp:send(Sock, Data) of
					ok->
						c_event_send(PPid,CaptureList,Sock,DR,Conf);
					{error,Reason}->
						log_register({log,"Server Down? CSocket Closed....",Reason,stdout}),
						PPid ! {close_proxy,self(),Sock},
						exit("CSocket Closed")
				end;
			   
			true->
				
				case gen_tcp:send(Sock, Data) of
					ok->
						
						log_register({log,"Send Data To Server : ",Data,stdout}),
						c_event_send(PPid,CaptureList,Sock,DR,Conf);
					
					{error,Reason}->
						
						% Developer Should Control Data That Has Error So We Can Not Capture Data %
						log_register({log,"Server Down? CSocket Closed....",Reason,stdout}),
						PPid ! {close_proxy,self(),Sock},
						exit("CSocket Closed")
				end
						
			end;
			   
		{close} ->
			log_register({log,"Destroyed Sender : ",self(),stdout}),
			exit("Natural")
	end.

c_event_recv(PPid,ListPidS,TPidS,Master,Sock,Conf=#config{})->
	% Link Two Process For Better Handling Pair Process %
	% link(TPidS),
	
	case gen_tcp:recv(Sock, 0) of
		{ok,B}->
			
			% For Mainplute Data %
			log_register({log,"Data Receive From Server : ",B,stdout}),
			
			% We Have Master And Replication Route %
			if Master == 1->
				log_register({log,"Data Receive From Master And Transfer To Peer : ",[B,ListPidS],stdout}),
				send_signal_list(ListPidS,{send,B});
			   
			true->
				% Silent If This Server Is Duplicate %
				log_register({log,"Data Receive From None Master : ",B,stdout})
			end,

			c_event_recv(PPid,ListPidS,TPidS,Master,Sock,Conf);
		
		{error,closed} ->
			log_register({log,"Destroyed Receiver recv: ",self(),stdout}),
			PPid ! {close_proxy,self(),Sock},
			exit("Natural");
		_->
			log_register({log,"Destroyed Receiver _: ",self(),stdout}),
			PPid ! {close_proxy,self(),Sock},
			exit("Natural")
	end,
	receive 
		{close} ->
			log_register({log,"Destroyed Receiver event: ",self(),stdout}),
			exit("Natural")
	end.


% Utility %
find_deaditem([],ListDead)-> ListDead;
find_deaditem([H|T],ListDead)->
	if H#peer.alive == 0->
		ListDead++[H];
	true->
		find_deaditem(T,ListDead)
	end.

find_isoitem([],Item)-> false;
find_isoitem([H|T],Item)->
	% Maybe Was Better Checking Port %
	if H#peer.p1port == Item#peer.p1port ->
		true;
	true->
		find_isoitem(T,Item)
	end.

find_haitem([],Item)->Item;
find_haitem([H|T],Item)->
	{State,DR}=H,
	if (State == true) and (DR#peer.p1port == Item#peer.p1port) ->
		   DR;
	true->
		find_haitem(T,Item)
	end.

send_signal_list([],Struct)-> ok;
send_signal_list([H|T],Struct)->
	H ! Struct,
	send_signal_list(T,Struct).

send_struct_Predictlist([],Struct,Cdiv,Cfun)-> ok;
send_struct_Predictlist([H|T],Struct,Cdiv,Cfun)->
	Res=Cfun(Cdiv),
	if Res == true ->
		log_register({log,"I Should Send Data To Item : ",H,stdout}),
		H ! Struct,
		send_struct_Predictlist(T,Struct,Cdiv+1,Cfun);
	true->
		send_struct_Predictlist(T,Struct,Cdiv+1,Cfun)
	end.

link_pidlist([])-> ok;
link_pidlist([H|T])->
	link(H).

log_register(Struct)->
	Pid=erlang:whereis(wrouteL),
	Pid ! Struct.

ha_register(Struct,WHA)->
	Pid=erlang:whereis(list_to_atom(WHA)),
	Pid ! Struct.
	

