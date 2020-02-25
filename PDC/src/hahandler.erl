%% @author root
%% @doc @todo Add description to hahandler.


-module(hahandler).

-export([handler/3,checklayer/3]).

-include("types.hrl").


handler(PPid,DR,Conf=#config{})->
	receive
		{emergency,DRA}->
			
			if Conf#config.ha == 1->
				
				log_register({log,"Emergency Sig Received....",DR#peer.p1port,stdout}),
			
				Res=checklayer(PPid,DR,Conf),
			
				log_register({log,"Update Emergency Sig To....",Res,stdout}),
			
				handler(PPid, Res, Conf);
			   
			true ->
				
				log_register({log,"HA Disabled In Config....","",stdout}),
				handler(PPid, DR, Conf)

			end;
	
		_->

			handler(PPid, DR, Conf)
	
	after 6000 ->
			if Conf#config.ha == 1->

				Res=checklayer(PPid,DR,Conf),
				handler(PPid, Res, Conf);

			true->
				
				log_register({log,"HA Disabled In Config....","",stdout}),
				handler(PPid, DR, Conf)

			end
	end.

checklayer(PPid,DR,Conf=#config{})->
	
	log_register({log,"State Interval 8s Starting...","",stdout}),

	{State,NewDR}=state(DR,DR#peer.duplicates,3),
			
	log_register({log,"State : ",{State,NewDR},stdout}),
			
	if State == false ->
		PPid ! {fulldestroy,DR},
		DR;
	(State == true) and (NewDR /= DR) ->
			% Upper Priority Update %
			% Now Change DR Alive State And Master State %
			% Reverse From Non-Master That Is Master To Duplicate Not Implement :) %
			% So We Have RoundRobine For All Alive That Are Full Data Now %
			% This Is Dependent What Is Server After This Node : 1-apache 2-mysql , apache do not need update but mysql need %
			PPid ! {isolate,self(),DR},
					
			UpdateDR=change(DR,NewDR),
			
			log_register({log,"Updated HA DR : ",UpdateDR,stdout}),
					
			PPid ! {changeHA,UpdateDR},
					
			PPid ! {unisolate,self(),DR},
					
			UpdateDR;
	true->
			% Update Other Replica Set If NewDR State Was Equal To DR Check Other Node %
			UpdateDR=checkOther(DR#peer.duplicates,DR#peer.replica,DR,Conf),
			
			if UpdateDR /= DR->
				PPid ! {isolate,self(),UpdateDR},

				log_register({log,"Updated DR (Reason : Alive) : ",UpdateDR,stdout}),
					
				PPid ! {changeHA,UpdateDR},
					
				PPid ! {unisolate,self(),UpdateDR},
			
				UpdateDR;
			true->
				DR
			end
	end.

% Utility %
state(DR,[],CN)->
	if CN == 0 ->
		{false,DR};
	true->
		case gen_tcp:connect(DR#peer.p2, DR#peer.p2port, [binary,{active,false},{packet,0}],3000) of
			{ok,Sc}->
				gen_tcp:close(Sc),
				{true,DR};
			{error,Reason}->
				state(DR,[],CN-1)
		end
	end;
state(DR,[H|T],CN)-> 
	if CN == 0 ->
		state(H,T,CN+3);
	true->
		case gen_tcp:connect(DR#peer.p2, DR#peer.p2port, [binary,{active,false},{packet,0}],4000) of
			{ok,Sc}->
				gen_tcp:close(Sc),
				
				% Before Return, Check Is It Duplicate And Is Master Came Up %
				{true,DR};
			
			{error,Reason}->
				state(DR,[H|T],CN-1)
		end
	end.

change(DR,NewDR)->
	if DR /= NewDR->
		   % Change Master to Replica That Is Off Master Bit=0 Alive Bit=0 Last Bit=Last%
		   DRC=#peer{p1=DR#peer.p1,p1port=DR#peer.p1port,p2=DR#peer.p2,p2port=DR#peer.p2port,master=0,last=DR#peer.last,alive=0,replica=DR#peer.replica,duplicates=[]},
		   DUPList=DR#peer.duplicates,
		   DUPList1=lists:delete(NewDR, DUPList),
		   DUPList2=DUPList1++[DRC],
		   
		   DRTMP=#peer{p1=NewDR#peer.p1,p1port=NewDR#peer.p1port,p2=NewDR#peer.p2,p2port=NewDR#peer.p2port,master=1,last=0,alive=1,replica=NewDR#peer.replica,duplicates=DUPList2},
		   DRTMP;
	true->
		DR
	end.

checkOther([],IsReplica,FDR,Conf=#config{})->FDR;
checkOther([H|T],IsReplica,FDR,Conf=#config{})->
	if H#peer.alive == 0 ->
		log_register({log,"It is Offline Host So I Check It....",H,stdout}),
							
		case gen_tcp:connect(H#peer.p2, H#peer.p2port, [binary,{active,false},{packet,0}],3000) of
			{ok,Sc}->
				gen_tcp:close(Sc),

				% Send All Data To Master And Wait For Action But Before We Should Stop Duplicate %
				% Send Signal To Server To Wait And Isolate Server %
				log_register({log,"Host Came UP : ",H,stdout}),
				
				% Now Send All Data To Master After A Milisec %
				if IsReplica == 1 ->
					if Conf#config.recovery == 1 ->
						   
						log_register({log,"Call ~~Recovery Method~~ (Was In Replication Mode)","",stdout}),
						log_register({log,"Recovery Method Not Implemented...We Just Change State","",stdout}),
						
						NewDR=updateAliveDR(FDR,H,0,H#peer.last,1),
						
						checkOther(T,IsReplica,NewDR,Conf);
					   
				   	true->
						
						log_register({log,"Disabled ~~Recovery Method~~","",stdout}),
						
						NewDR=updateAliveDR(FDR,H,0,H#peer.last,1),
						checkOther(T,IsReplica,NewDR,Conf)
					
					end;
				true->
					% Update Node Now %
					NewDR=updateAliveDR(FDR,H,0,H#peer.last,1),
					checkOther(T,IsReplica,NewDR,Conf)
				
				end;
			
			{error,Reason}->
				
				log_register({log,"Host is Down Yet...",H,stdout}),
				checkOther(T,IsReplica,FDR,Conf)
		
		end;
	true->
		log_register({log,"It Has Alive Bit WithOut Check Is It Real....",H,stdout}),
		
		% Check If Duplicate Go Down But Bit Do Not Check
		case gen_tcp:connect(H#peer.p2, H#peer.p2port, [binary,{active,false},{packet,0}],3000) of
			{ok,Sc}->
				
				checkOther(T,IsReplica,FDR,Conf);
			
			{error,Reason}->
				
				log_register({log,"Host is Down But Bit Alive Do Not Change...",H,stdout}),
				NewDR=updateAliveDR(FDR,H,0,H#peer.last,0),
				
				checkOther(T,IsReplica,NewDR,Conf)
		
		end
	end.

updateAliveDR(FDR,DR,IsMaster,LastAttr,IsAlive)->
	DUP=lists:delete(DR, FDR#peer.duplicates),
	DRC=#peer{p1=DR#peer.p1,p1port=DR#peer.p1port,p2=DR#peer.p2,p2port=DR#peer.p2port,master=IsMaster,last=LastAttr,alive=IsAlive,replica=DR#peer.replica,duplicates=[]},
	FDRTMP=#peer{p1=FDR#peer.p1,p1port=FDR#peer.p1port,p2=FDR#peer.p2,p2port=FDR#peer.p2port,master=FDR#peer.master,last=FDR#peer.last,alive=FDR#peer.alive,replica=FDR#peer.replica,duplicates=DUP++[DRC]},
	FDRTMP.

log_register(Struct)->
	Pid=erlang:whereis(wrouteL),
	Pid ! Struct.
	