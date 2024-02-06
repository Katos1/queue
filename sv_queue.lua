local priorityLevels<const> = {
  STAFF = 4,
  CLUB_PREMIUM = 3,
  CLUB_NORMAL = 2,
  DEFAULT = 1,
}

local queueStack = {} -- Holds the queue of players

local function shiftQueueStack(index)
  table.remove(queueStack, index)
end

local function getQueuePriorityLevel(source)
  local userId = GetUserId(source)

  if userId then
    if GetStaffPrivileges(userId) then
      return priorityLevels.STAFF
    end

    if IsUserClubPremiumMember(userId) then
      return priorityLevels.CLUB_PREMIUM
    end

    if IsUserClubMember(userId) then
      return priorityLevels.CLUB_NORMAL
    end
  end

  return priorityLevels.DEFAULT
end

local function getQueuePosition(source)
  for position, playerContext in ipairs(queueStack) do
    if playerContext.source == source then
      return position
    end
  end

  return -1
end

local function sortQueueByPriority()
  table.sort(queueStack, function(a, b)
    return a.priority > b.priority
  end)
end

function IsPlayerInQueue(source)
  return getQueuePosition(source) ~= -1
end

local function emitQueueMessage(source, deferrals)
  return function()
    while IsPlayerInQueue(source) do
      local position = getQueuePosition(source)
      local deferralMessage = ("You are %s / %s in Queue"):format(position, #queueStack)
      
      -- Verify connection
      if GetPlayerPing(source) == 0 then
        deferrals.done("Lost connection with server")  
        
        if IsPlayerInQueue(source) then
          shiftQueueStack(position)  
        end
        
        break
      end
      
      for i = 1, 3 do
        deferrals.update(deferralMessage .. string.rep(".", i))
        Wait(500)
      end
      
      deferrals.update(deferralMessage)
      Wait(1000)
    end
  end
end

local function pushQueueStack(source, deferrals, fwdPromise)
  local priorityLevel = getQueuePriorityLevel(source)

  table.insert(queueStack, {
    source = source, 
    deferrals = deferrals, 
    promise = fwdPromise, 
    priority = priorityLevel or 0
  })
  
  sortQueueByPriority()
  CreateThread(emitQueueMessage(source, deferrals))
end

local function checkQueue(source, deferrals)
  local serverSlots = GetServerSlots()
  
  if GetPlayerCount() + 1 > serverSlots then
    local queuePromise = promise.new()

    pushQueueStack(source, deferrals, queuePromise)
    queuePromise:resolve()
    
    return Citizen.Await(queuePromise)
  end

  deferrals.done()
end

local function processQueueStack()
  local serverSlots = GetConvarInt("sv_maxclients", 1024)
  local playerCount = GetNumPlayerIndices()
  local processDifference = serverSlots - playerCount
  
  for position = 1, processDifference do
    local playerContext = queueStack[position]
    
    if playerContext then
      playerContext.deferrals.done()
    end
  end
end

AddEventHandler("playerConnecting", function(_, _, deferrals)
  local source = source
  checkQueue(source, deferrals)
end)

AddEventHandler("playerJoining", function(oldSource)
  local source = tonumber(oldSource)

  if IsPlayerInQueue(source) then
    local position = getQueuePosition(source)
    local playerContext = queueStack[position]
    
    if playerContext then
      playerContext.promise:resolve()
      shiftQueueStack(position)
    end
  end
end)

CreateThread(function()
  while true do
    Wait(1000)

    -- There is atleast one player in the queue
    if #queueStack > 0 then 
      processQueueStack()
    end
  end
end)