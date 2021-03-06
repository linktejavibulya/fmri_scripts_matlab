function [ps_all]=connectivitysim(data,ftbl,varargin)
% DO NOT CALL DIRECTLY; call from makeroccurves
% compute ps from permutation-based comparisons with and without effect added
% use two groups or within group pre/post treatment

% TODO: speed up by creating two separate scripts:
% 1. generate data with/without effect sizes


%% Parse input
p = inputParser;

defaultniterations=50;
defaultdofalsepositive=1;
defaultdofalsenegative=0;
defaulteffectsize=0.5;
defaultnsubs=max(ftbl.Subject);
defaultnruns=1;
defaultusesamesubs=0; % if want same subs in both groups; else, groups will use different subs
defaultdoindividual=0;

addParameter(p,'iterations',defaultniterations,@isnumeric);
addParameter(p,'dofalsepositive',defaultdofalsepositive,@isnumeric);
addParameter(p,'dofalsenegative',defaultdofalsenegative,@isnumeric);
addParameter(p,'effectsize',defaulteffectsize,@isnumeric);
addParameter(p,'nsubs',defaultnsubs,@isnumeric);
addParameter(p,'nruns',defaultnruns,@isnumeric);
addParameter(p,'usesamesubs',defaultusesamesubs,@isnumeric);
addParameter(p,'doindividual',defaultdoindividual,@isnumeric);

parse(p,varargin{:});

niterations = p.Results.iterations;
dofalsepositive = p.Results.dofalsepositive;
dofalsenegative = p.Results.dofalsenegative;
effectsize=p.Results.effectsize;
nsubs=p.Results.nsubs;
nruns=p.Results.nruns;
usesamesubs=p.Results.usesamesubs;
doindividual=p.Results.doindividual;

clearvars p



%% Setup I: define data

nsubs_tot=max(ftbl.Subject);
nsess=max(ftbl.Session);
data_msk=nan(nsubs_tot*nsess,size(data,2));

% average over nruns
if nruns>1
    for thissub=1:nsubs_tot
        for thissess=1:nsess
            theseids=ftbl.Subject==thissub & ftbl.Session==thissess & ftbl.Run<=nruns;
            data_msk((thissub-1)*nsess+thissess,:)=mean(data(theseids,:),1);
        end
    end
else
    
    if usesamesubs
        data_msk=data(ftbl.Run==1,:);
    else
        data_msk=data(ftbl.Run==1 & ftbl.Session==1,:);
        nsess=1;
    end
end

clearvars data tmp

% nscans_new=size(data_msk,1);
% ids=reshape([1:nscans_new],nsess,nsubs_tot)';

%% Setup II: Randomize scans into groups
balanceprepost=0;

if usesamesubs % same subjects in each group but different scans
    selected_subs=arrayfun(@(x)randperm(nsubs_tot,nsubs),(1:niterations)','UniformOutput',0);
    selected_subs=cell2mat(selected_subs')';
    selected_subs=[selected_subs selected_subs];
    selected_subs=(selected_subs-1)*nsess;
    
    if ~balanceprepost % select 2 out of 4 sessions nsubs times. Do niterations.
        ngroups=2;
        ids_preset=arrayfun(@(x)randperm(nsess,ngroups),(1:nsubs*niterations)','UniformOutput',0);
        ids_preset=cell2mat(ids_preset);
        ids_preset=ids_preset+selected_subs;
        
    else  % make balanced vector of [2 1; 1 2] that is nsubs long. Do niterations.
        secondsess=length(nsess)/2+1;
        tmp=[secondsess 1 1 secondsess]; % use only first and mid+1 session
        t=repmat(tmp,1,nsubs/2*niterations); % (divide by 2 here bc reshaping next line)
        t=reshape(t,2,nsubs*niterations)';
        
        t2=arrayfun(@(x)randperm(nsubs),(1:niterations)','UniformOutput',0);
        t2=cell2mat(t2')';
        
        ids_preset=[t(t2,1) t(t2,2)];
        ids_preset=ids_preset+selected_subs;
        
    end
    
    
else % use different subjects in each group
    
    if nsubs>nsubs_tot/2 % can only have max of half indvid in group
        nsubs=nsubs/2;
    end
    
    t=arrayfun(@(x)randperm(nsubs_tot,nsubs*2),(1:niterations)','UniformOutput',0);
    t=cell2mat(t)';

    if ~doindividual
    	t=[t(1:nsubs,:) t(nsubs+1:nsubs*2,:)];
    	ids_preset=reshape(t,nsubs*niterations,2);
    else
    	ids_preset=reshape(t,prod(size(t)),1);
    end    

end




%% Simulation

% make function handle for ttest depending on type
if usesamesubs||doindividual  ttest_fh='ttest'; % paired ttest for same subs OR one-sample t-test
else ttest_fh='ttest2'; % two sample (unpaired) for different subs
end
ttest_fh=str2func(ttest_fh);

% preallocate
ps_all{2}=[];

if doindividual
    
    for i=1:niterations
        % assigndata
        
        if usesamesubs % pre-/post- change
            ids1=ids_preset((i-1)*nsubs+1:i*nsubs,1);
            ids2=ids_preset((i-1)*nsubs+1:i*nsubs,2);
            data_gr1=data_msk(ids1(1:(end-1)),:)-data_msk(ids2(1:(end-1)),:);
            data_gr2=data_msk(ids1(end),:)-data_msk(ids2(end),:);
        else % choose single person
            ids1=ids_preset((i-1)*2*nsubs+1:i*2*nsubs,1);
	    data_gr1=data_msk(ids1(1:(end-1)),:); % group - reference group or condition (pre)
            data_gr2=data_msk(ids1(end),:); % individual
        end
        
        if dofalsepositive
            data_gr2=repmat(data_gr2,size(data_gr1,1),1);
            [~,ps]=ttest_fh(data_gr1-data_gr2);
            % this is equivalent to: [~,ps(edge)]=ttest_fh(data_gr1(:,edge),data_gr2(1,edge))
            ps_all{1}(:,i)=ps;
        end
        if dofalsenegative
            scaling1=std(data_gr1);
            scaling=repmat(scaling1,size(data_gr1,1),1);
            [~,ps]=ttest_fh(data_gr1-data_gr2+effectsize*scaling);
            ps_all{2}(:,i)=ps;
        end
    end
    
else
    
    if dofalsepositive
        for i=1:niterations
            % assigndata
            ids1=ids_preset((i-1)*nsubs+1:i*nsubs,1);
            ids2=ids_preset((i-1)*nsubs+1:i*nsubs,2);
            data_gr1=data_msk(ids1,:); % group 1 - reference group or condition (pre)
            data_gr2=data_msk(ids2,:); % group 2 - treatment group or condition (post)
            
            % check for false positives
            [~,ps]=ttest_fh(data_gr1,data_gr2); % consider: [~,ps]=ttest(data_gr1,data_gr2,'Vartype','unequal');
            ps_all{1}(:,i)=ps;
            
        end
    end
    
    % separate as to break dependence btw FP and FN
    if dofalsenegative
        for i=1:niterations
            % assigndata
            ids1=ids_preset((i-1)*nsubs+1:i*nsubs,1);
            ids2=ids_preset((i-1)*nsubs+1:i*nsubs,2);
            data_gr1=data_msk(ids1,:); % group 1 - reference group or condition (pre)
            data_gr2=data_msk(ids2,:); % group 2 - treatment group or condition (post)
            
            % check for false negatives
            scaling1=std(data_gr2,1);
            scaling=repmat(scaling1,size(data_gr2,1),1);  % scaling for effect size
            [~,ps]=ttest_fh(data_gr1,data_gr2+effectsize*scaling);
            ps_all{2}(:,i)=ps;
            %  boxplot(std(data_gr2,1))
            %  NOTE: to convert d to r: r = d/sqrt(d^2+4)
        end
    end
    
    
end


%% plot
% 
% if makeplot
%     
%     scalingfactor=100/length(ps); % for making percents
%     
%     figure
%     for thisplot=1:size(counts,2)
%         h=histogram(counts(:,thisplot)*scalingfactor);
%         histpeaks(thisplot)=max(h.Values);
%         hold on
%     end
%     
%     yl=ylim;
%     plot([nominalval*scalingfactor nominalval*scalingfactor],[0 yl(2)],'r')
%     
%     hold off
%     
% end
