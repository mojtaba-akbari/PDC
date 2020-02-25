%% Define Structure %%
-record(peer,{p1="",p1port=0,p2="",p2port=0,master=0,last=0,alive=1,replica=1,duplicates=[]}).
-record(config,{logging=0,logfile="",capture=0,capturefile="",recovery=1,ha=1}).