ClassicLFGDungeonGroupManager = {}
ClassicLFGDungeonGroupManager.__index = ClassicLFGDungeonGroupManager

setmetatable(ClassicLFGDungeonGroupManager, {
    __call = function (cls, ...)
        return cls.new(...)
    end,
})

function ClassicLFGDungeonGroupManager.new(dungeon, leader, title, description, source, members)
    local self = setmetatable({}, ClassicLFGDungeonGroupManager)
    self.DungeonGroup = nil
    self.Applicants = ClassicLFGLinkedList()
    self.Frame = CreateFrame("Frame")
    self.Frame:RegisterEvent("PARTY_INVITE_REQUEST")
    self.Frame:RegisterEvent("GROUP_ROSTER_UPDATE")
    self.Frame:RegisterEvent("GROUP_JOINED")
    self.Frame:RegisterEvent("GROUP_LEFT")
    self.Frame:RegisterEvent("RAID_ROSTER_UPDATE")
    self.Frame:RegisterEvent("PARTY_INVITE_REQUEST")
    self.Frame:RegisterEvent("PARTY_INVITE_REQUEST")
    self.Frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    self.Frame:RegisterEvent("PLAYER_LEAVING_WORLD")
    self.Frame:RegisterEvent("CHAT_MSG_SYSTEM")
    self.Frame:RegisterEvent("CHAT_MSG_CHANNEL_JOIN")
    self.Frame:RegisterEvent("PARTY_LEADER_CHANGED")
    self.Frame:SetScript("OnEvent", function(_, event, ...)
        if (event == "CHAT_MSG_SYSTEM") then

            local message = ...
            if(self:IsListed() and message:find(ClassicLFG.Locale[" declines your group invitation."])) then
                local playerName = message:gsub(ClassicLFG.Locale[" declines your group invitation."], "")
                self:ApplicantInviteDeclined(ClassicLFGPlayer(playerName, "", "", "", ""))
            end

            if(self:IsListed() and message:find(ClassicLFG.Locale[" joins the party."])) then
                ClassicLFG:DebugPrint("Player joined the party!")
                local playerName = message:gsub(ClassicLFG.Locale[" joins the party."], "")
                local index = self.Applicants:Contains(ClassicLFGPlayer(playerName))
                if (index ~= nil) then
                    self:ApplicantInviteAccepted(self.Applicants:GetItem(index))
                else
                    self:ApplicantInviteAccepted(ClassicLFGPlayer(playerName))
                end
            end

            if(self:IsListed() and message:find(ClassicLFG.Locale[" leaves the party."])) then
                local playerName = message:gsub(ClassicLFG.Locale[" leaves the party."], "")
                ClassicLFG:DebugPrint(playerName .. " left the party!")
                ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupMemberLeft, ClassicLFGPlayer(playerName))
            end

            if((message:find(ClassicLFG.Locale["Your group has been disbanded."]) or
            message:find(ClassicLFG.Locale["You leave the group."]) or
            message:find(ClassicLFG.Locale["You have been removed from the group."]))) then
                 ClassicLFG:DebugPrint("Left party.")
                if (self:IsListed() and self.DungeonGroup.Leader.Name ~= UnitName("player")) then
                    ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupLeft, self.DungeonGroup)
                else
                    if (self:IsListed()) then
                        ClassicLFGLinkedList.Clear(self.DungeonGroup.Members)
                        ClassicLFGLinkedList.AddItem(self.DungeonGroup.Members, ClassicLFGPlayer())
                    end
                end
            end
        end

        if(self:IsListed() and event == "PARTY_LEADER_CHANGED") then
            if (UnitIsGroupLeader(UnitName("player")) == false and self.BroadcastTicker ~= nil) then
                self:CancelBroadcast()
            end

            if (UnitIsGroupLeader(UnitName("player")) == true and self.BroadcastTicker == nil) then
                self:StartBroadcast()
            end

            for i = 0, self.DungeonGroup.Members.Size - 1 do
                local player = ClassicLFGLinkedList.GetItem(self.DungeonGroup.Members, i)
                
                if (UnitIsGroupLeader(player.Name) == true) then
                    local oldGroup = self.DungeonGroup
                    oldGroup.Leader = player
                    self:UpdateGroup(oldGroup)
                    break
                end
            end
        end

        if (event == "CHAT_MSG_CHANNEL_JOIN") then
            local _, playerName, _, channelId, channelName = ...
            if (tonumber(channelId:sub(0,1)) == ClassicLFG.Config.Network.Channel.Id) then
                self:HandleDataRequest(nil, playerName)
            end
        end
        
        if (event == "GROUP_ROSTER_UPDATE") then
            if (self.DungeonGroup) then
                --self.DungeonGroup:Sync()
                for i = 1, GetNumGroupMembers() do
                    local playerName = GetRaidRosterInfo(i)
                    local player = ClassicLFGPlayer(playerName)
                    for k=0, self.Applicants.Size - 1 do
                        if (self.Applicants:GetItem(k).Name == playerName) then
                            self:ApplicantInviteAccepted(player)
                            break
                        end
                    end
                end
            end
        end

        if (event == "PARTY_INVITE_REQUEST") then
            -- ToDo: Only Accept if the leader is in one of the groups you applied to.
            --AcceptGroup()
            --StaticPopup1:Hide()
        end
    end)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.RequestData, self, self.HandleDataRequest)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.ApplyForGroup, self, self.HandleApplications)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.DungeonGroupSyncRequest, self, self.HandleDungeonGroupSyncRequest)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.DungeonGroupSyncResponse, self, self.HandleDungeonGroupSyncResponse)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.DungeonGroupJoined, self, self.HandleDungeonGroupJoined)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.DungeonGroupLeft, self, self.HandleDungeonGroupLeft)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.GroupDelisted, self, self.HandleGroupDelisted)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.GroupListed, self, self.HandleGroupListed)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.DungeonGroupUpdated, self, self.HandleGroupUpdated)
    ClassicLFG.EventBus:RegisterCallback(ClassicLFG.Config.Events.DungeonGroupMemberLeft, self, self.HandleDungeonGroupMemberLeft)
    return self
end

function ClassicLFGDungeonGroupManager:CancelBroadcast()
    ClassicLFG:DebugPrint("Canceled broadcasting dungeon group")
    self.BroadcastTicker:Cancel()
    self.BroadcastTicker = nil
end

function ClassicLFGDungeonGroupManager:StartBroadcast()
    ClassicLFG:DebugPrint("Started broadcasting dungeon group")
    SendChatMessage(self:GetBroadcastMessage(), "CHANNEL", nil, GetChannelName(ClassicLFG.DB.profile.BroadcastDungeonGroupChannel))
    self.BroadcastTicker = C_Timer.NewTicker(ClassicLFG.DB.profile.BroadcastDungeonGroupInterval, function()
        ClassicLFG:DebugPrint("Broadcast Ticker tick")
        if (self:IsListed()) then
            -- Prevent group from being delisted on other clients
            self:UpdateGroup(self.DungeonGroup)
            SendChatMessage(self:GetBroadcastMessage(), "CHANNEL", nil, GetChannelName(ClassicLFG.DB.profile.BroadcastDungeonGroupChannel))
        end
    end)
end

function ClassicLFGDungeonGroupManager:GetBroadcastMessage()
    if (self.DungeonGroup.Dungeon.Name == ClassicLFG.Dungeon.Custom.Name) then
        return self.DungeonGroup.Title
    else 
        return "LFM \"" .. self.DungeonGroup.Dungeon.Name .. "\": " .. self.DungeonGroup.Title
    end    
end


function ClassicLFGDungeonGroupManager:HandleDataRequest(object, sender)
    if (self.DungeonGroup ~= nil) then
        local characterName = sender:SplitString("-")[1]
        if (self.DungeonGroup.Leader.Name == UnitName("player") or characterName == self.DungeonGroup.Leader.Name) then
            ClassicLFG.Network:SendObject(
                ClassicLFG.Config.Events.GroupListed,
                self.DungeonGroup,
                "WHISPER",
                sender)
        end
    end
end

function ClassicLFGDungeonGroupManager:HandleDungeonGroupMemberLeft(player)
    if (self:IsListed()) then
        self:RemoveMember(player)
        if (UnitIsGroupLeader("player") == true) then
            self:UpdateGroup(self.DungeonGroup)
        end
    end
end

function ClassicLFGDungeonGroupManager:HandleGroupDelisted(dungeonGroup)
    if (self.DungeonGroup ~= nil and dungeonGroup.Hash == self.DungeonGroup.Hash) then
        ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupLeft, self.DungeonGroup)
    end
end

function ClassicLFGDungeonGroupManager:HandleGroupListed(dungeonGroup)
    if (UnitIsGroupLeader(dungeonGroup.Leader.Name) == true and dungeonGroup.Source.Type == "ADDON") then
        ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupJoined, dungeonGroup)
    end
end

function ClassicLFGDungeonGroupManager:HandleGroupUpdated(dungeonGroup)
    if (self:IsListed() and dungeonGroup.Hash == self.DungeonGroup.Hash) then
        self.DungeonGroup = dungeonGroup
    end
end

function ClassicLFGDungeonGroupManager:HandleDungeonGroupJoined(dungeonGroup)
    self.DungeonGroup = dungeonGroup
    if (UnitIsGroupLeader("player") == true or not IsInGroup()) then
        self:StartBroadcast()
    end
end

function ClassicLFGDungeonGroupManager:HandleDungeonGroupSyncRequest(_, sender)
    if (self.DungeonGroup ~= nil) then
        ClassicLFG.Network:SendObject(
            ClassicLFG.Config.Events.DungeonGroupSyncResponse,
            self.DungeonGroup,
            "WHISPER",
            sender)
    end
end

function ClassicLFGDungeonGroupManager:HandleDungeonGroupSyncResponse(object)
    if (self.DungeonGroup == nil) then
        self.DungeonGroup = object
        ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupJoined, self.DungeonGroup)
    else
        self.DungeonGroup = object
        ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupUpdated, self.DungeonGroup)
    end
end

function ClassicLFGDungeonGroupManager:InitGroup(title, dungeon, description)
    local dungeonGroup = ClassicLFGDungeonGroup(dungeon, nil, title, description)
    for i = 1, GetNumGroupMembers() do
        local playerName = GetRaidRosterInfo(i)
        if (playerName ~= UnitName("player")) then
            dungeonGroup:AddMember(ClassicLFGPlayer(playerName))
        end
    end
    return dungeonGroup
end

function ClassicLFGDungeonGroupManager:ListGroup(dungeonGroup)
    self.DungeonGroup = dungeonGroup
    ClassicLFGDungeonGroup.AddMember(self.DungeonGroup, ClassicLFGPlayer(UnitName("player")))
    ClassicLFG.Network:SendObject(
        ClassicLFG.Config.Events.GroupListed,
        dungeonGroup,
        "CHANNEL",
        ClassicLFG.Config.Network.Channel.Id)
    ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupJoined, self.DungeonGroup)
end

function ClassicLFGDungeonGroupManager:IsListed()
    return self.DungeonGroup ~= nil
end

function ClassicLFGDungeonGroupManager:DequeueGroup()
    if (self:IsListed()) then
        ClassicLFG.Network:SendObject(
            ClassicLFG.Config.Events.GroupDelisted,
            self.DungeonGroup,
            "CHANNEL",
            ClassicLFG.Config.Network.Channel.Id)
        ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.DungeonGroupLeft, self.DungeonGroup)
    end
end

function ClassicLFGDungeonGroupManager:UpdateGroup(dungeonGroup)
    if (self.DungeonGroup ~= nil) then
        self.DungeonGroup.Dungeon = dungeonGroup.Dungeon
        self.DungeonGroup.Description = dungeonGroup.Description
        self.DungeonGroup.Title = dungeonGroup.Title
        self.DungeonGroup.UpdateTime = GetTime()
        ClassicLFG.Network:SendObject(
            ClassicLFG.Config.Events.DungeonGroupUpdated,
            self.DungeonGroup,
            "CHANNEL",
            ClassicLFG.Config.Network.Channel.Id)
    end
end

function ClassicLFGDungeonGroupManager:HandleDungeonGroupLeft(dungeonGroup)
    if (dungeonGroup.Leader.Name == UnitName("player")) then
        self:CancelBroadcast()
    end
    self.DungeonGroup = nil
end

function ClassicLFGDungeonGroupManager:HandleApplications(applicant)
    if (not ClassicLFG:IsIgnored(applicant.Name)) then
        local index = self.Applicants:ContainsWithEqualsFunction(applicant, function(item1, item2)
            return item1.Name == item2.Name
        end)
        if (index == nil) then
            self:AddApplicant(applicant)
        end
        ClassicLFG.Network:SendObject(
            ClassicLFG.Config.Events.ApplyForGroup,
            applicant,
            "PARTY")
    end
end

function ClassicLFGDungeonGroupManager:AddApplicant(applicant)
    self.Applicants:AddItem(applicant)
    ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.ApplicantReceived, applicant)
end

function ClassicLFGDungeonGroupManager:RemoveApplicant(applicant)
    local index = self.Applicants:ContainsWithEqualsFunction(applicant, function(item1, item2)
        return item1.Name == item2.Name
    end)
    if (index ~= nil) then
        self.Applicants:RemoveItem(index)
    end
end

function ClassicLFGDungeonGroupManager:RemoveMember(member)
    local index = ClassicLFGLinkedList.ContainsWithEqualsFunction(self.DungeonGroup.Members, member, function(item1, item2)
        return item1.Name == item2.Name
    end)
    if (index ~= nil) then
        ClassicLFGLinkedList.RemoveItem(self.DungeonGroup.Members, index)
    end
end

function ClassicLFGDungeonGroupManager:ApplicantDeclined(applicant)
    self:RemoveApplicant(applicant)
    ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.ApplicantDeclined, applicant)
    ClassicLFG.Network:SendObject(ClassicLFG.Config.Events.DeclineApplicant, self.DungeonGroup, "WHISPER", applicant.Name)
    ClassicLFG.Network:SendObject(
            ClassicLFG.Config.Events.DeclineApplicant,
            applicant,
            "PARTY")
end

function ClassicLFGDungeonGroupManager:ApplicantInvited(applicant)
    InviteUnit(applicant.Name)
    ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.ApplicantInvited, applicant)
end

function ClassicLFGDungeonGroupManager:ApplicantInviteAccepted(applicant)
    self:RemoveApplicant(applicant)
    ClassicLFGDungeonGroup.AddMember(self.DungeonGroup, applicant)
    ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.ApplicantInviteAccepted, applicant)
    
    if (self.DungeonGroup.Members.Size == 5) then
        self:DequeueGroup()
    else
        ClassicLFG.Network:SendObject(ClassicLFG.Config.Events.DungeonGroupJoined, self.DungeonGroup, "WHISPER", applicant.Name)
        if (UnitIsGroupLeader("player") == true) then
            self:UpdateGroup(self.DungeonGroup)
        end
    end
end

function ClassicLFGDungeonGroupManager:ApplicantInviteDeclined(applicant)
    self:RemoveApplicant(applicant)
    ClassicLFG.EventBus:PublishEvent(ClassicLFG.Config.Events.ApplicantInviteDeclined, applicant)
end

ClassicLFG.DungeonGroupManager = ClassicLFGDungeonGroupManager()