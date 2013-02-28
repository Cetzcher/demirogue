require 'Graph'
require 'GraphGrammar'
require 'AABB'
require 'Vector'
require 'geometry'
require 'graph2D'

-- Basic graph editing for making grammar rule sets.
--
-- The screen is split into two panes, left and right.
-- The left pane holds the pattern graph.
-- THe right pane holds the substitute graph.

graphmode = {}

local config = {
	tolerance = 30,
}

local function _shadowf( x, y, ... )
	love.graphics.setColor(0, 0, 0, 255)

	local text = string.format(...)

	love.graphics.print(text, x-1, y-1)
	love.graphics.print(text, x-1, y+1)
	love.graphics.print(text, x+1, y-1)
	love.graphics.print(text, x+1, y+1)

	love.graphics.setColor(192, 192, 192, 255)

	love.graphics.print(text, x, y)
end

local function _save( state )
	-- Make a nice to save version of the state.

	-- { level }+
	-- level = { leftGraph = graph, rightGraph = graph, map = map }
	-- graph = { vertices = { vertex }+, edges = { { <index>, <index> } }+ }
	-- vertex = { <x>, <y>, side = 'left'|'right', tag = <string>, mapped = <boolean>|nil }
	-- map = { [<index>] = <index> }*

	local function _vertex( vertex )
		if vertex.side == 'left' then
			return {
				vertex[1],
				vertex[2],
				side = 'left',
				tags = table.copy(vertex.tags),
				lock = vertex.lock and true or false,
			}
		else
			return { 
				vertex[1],
				vertex[2],
				side = 'right',
				tag = vertex.tag,
				mapped = vertex.mapped and true or false,
			}
		end
	end

	local function _graph( graph )
		local vertexIndices = {}
		local nextVertexIndex = 1
		local vertices = {}

		for vertex, _ in pairs(graph.vertices) do
			local copy = _vertex(vertex)
			vertices[nextVertexIndex] = copy
			vertexIndices[vertex] = nextVertexIndex
			nextVertexIndex = nextVertexIndex + 1
		end

		local edges = {}

		for edge, endverts in pairs(graph.edges) do
			local vertex1Index = vertexIndices[endverts[1]]
			local vertex2Index = vertexIndices[endverts[2]]

			edges[#edges+1] = { vertex1Index, vertex2Index }
		end

		return { vertices = vertices, edges = edges }, vertexIndices
	end

	local function _level( level )
		local leftGraph, leftVertexIndices = _graph(level.leftGraph)
		local rightGraph, rightVertexIndices = _graph(level.rightGraph)

		local map = {}

		for leftVertex, rightVertex in pairs(level.map) do
			map[leftVertexIndices[leftVertex]] = rightVertexIndices[rightVertex]
		end

		return {
			leftGraph = leftGraph,
			rightGraph = rightGraph,
			map = map
		}
	end

	local levels = {}

	for index, level in ipairs(state.stack) do
		local copy = _level(level)
		levels[index] = copy
	end

	return table.compile(levels)	
end

local function _load( data )
	-- Make a nice to save version of the state.

	-- { level }+
	-- level = { leftGraph = graph, rightGraph = graph, map = map }
	-- graph = { vertices = { vertex }+, edges = { { <index>, <index> } }+ }
	-- vertex = { <x>, <y>, side = 'left'|'right', tag = <string>, mapped = <boolean>|nil }
	-- map = { [<index>] = <index> }*

	local function _vertex( vertex )
		if vertex.side == 'left' then
			return {
				vertex[1],
				vertex[2],
				side = 'left',
				tags = table.copy(vertex.tags),
				lock = vertex.lock and true or false,
			}
		else
			return { 
				vertex[1],
				vertex[2],
				side = 'right',
				tag = vertex.tag,
				mapped = vertex.mapped and true or false,
			}
		end
	end

	local function _graph( graph )
		local vertexIndices = {}

		local result = Graph.new()

		for index, vertex in ipairs(graph.vertices) do
			local copy = _vertex(vertex)
			result:addVertex(copy)
			vertexIndices[index] = copy
		end

		for _, edge in pairs(graph.edges) do
			local side = vertexIndices[edge[1]].side
			result:addEdge({ side = side }, vertexIndices[edge[1]], vertexIndices[edge[2]])
		end

		return result, vertexIndices
	end

	local function _level( level )
		local leftGraph, leftVertexIndices = _graph(level.leftGraph)
		local rightGraph, rightVertexIndices = _graph(level.rightGraph)

		local map = {}

		for leftVertexIndex, rightVertexIndex in pairs(level.map) do
			map[leftVertexIndices[leftVertexIndex]] = rightVertexIndices[rightVertexIndex]
		end

		return {
			leftGraph = leftGraph,
			rightGraph = rightGraph,
			map = map
		}
	end

	local result = {}

	for index, level in ipairs(data) do
		local copy = _level(level)

		result[index] = copy
	end

	return result	
end

local state = nil
local time = 0

function graphmode.update()
	time = time + love.timer.getDelta()

	if not state then
		local w, h = love.graphics.getWidth(), love.graphics.getHeight()
		local hw = w * 0.5

		local leftPane = AABB.new {
			xmin = 0,
			xmax = hw,
			ymin = 0,
			ymax = h,
		}

		local rightPane = AABB.new {
			xmin = hw,
			xmax = w,
			ymin = 0,
			ymax = h,
		}

		local leftGraph = Graph.new()
		local rightGraph = Graph.new()

		state = {
			leftPane = leftPane,
			rightPane = rightPane,
			stack = {
				{
					leftGraph = leftGraph,
					rightGraph = rightGraph,
					map = {},
				},
			},
			index = 1,
			selection = nil,
			edge = false,
		}
	end

	local level = state.stack[state.index]
	local mx, my = love.mouse.getX(), love.mouse.getY()
	local coord = Vector.new { mx, my }

	local distance = math.huge
	local selection = nil

	for vertex, _ in pairs(level.leftGraph.vertices) do
		local d = coord:toLength(vertex)
		if d < distance then
			distance = d
			selection = { type = 'vertex', vertex = vertex }
		end
	end

	for vertex, _ in pairs(level.rightGraph.vertices) do
		local d = coord:toLength(vertex)
		if d < distance then
			distance = d
			selection = { type = 'vertex', vertex = vertex }
		end
	end

	if distance > config.tolerance then
		selection = nil
	end

	-- What about an edge?
	if not selection then
		distance = math.huge

		for edge, endverts in pairs(level.leftGraph.edges) do
			local d = geometry.closestPointOnLine(endverts[1], endverts[2], coord):toLength(coord)

			if d < distance then
				distance = d
				selection = { type = 'edge', edge = edge }
			end
		end

		for edge, endverts in pairs(level.rightGraph.edges) do
			local d = geometry.closestPointOnLine(endverts[1], endverts[2], coord):toLength(coord)

			if d < distance then
				distance = d
				selection = { type = 'edge', edge = edge }
			end
		end
		
		if distance > config.tolerance then
			selection = nil
		end
	end

	if state.edge then
		assert(state.selection and state.selection.type == 'vertex')

		local current = state.selection.vertex

		if selection and selection.type == 'vertex' then
			local different = current ~= selection.vertex
			local sameSide = current.side == selection.vertex.side

			if different and sameSide then
				local graph = (current.side == 'left') and level.leftGraph or level.rightGraph

				if not graph:isPeer(current, selection.vertex) then
					graph:addEdge({ side = current.side }, current, selection.vertex)
				end
			end
		end
	else
		if selection and distance < config.tolerance then
			state.selection = selection
		else
			state.selection = nil
		end
	end
end

local tabbed = false

local function _tags( vertex )
	assert(vertex.side == 'left')

	local parts = {}

	for tag, _ in pairs(vertex.tags) do
		parts[#parts+1] = tag
	end

	table.sort(parts)

	return table.concat(parts, ',')
end

function graphmode.draw()
	local w, h = love.graphics.getWidth(), love.graphics.getHeight()
	local screen = AABB.new {
		xmin = 0,
		xmax = w,
		ymin = 0,
		ymax = h,
	}

	if not state.show then
		local hw = w * 0.5

		-- Dividing line.
		love.graphics.setColor(255, 255, 255, 255)
		love.graphics.setLine(1, 'rough')
		love.graphics.line(hw, 0, hw, h)

		local level = state.stack[state.index]

		-- Highlight any selection.
		if state.selection then
			local selection = state.selection

			love.graphics.setColor(255, 255, 0, 255)

			if selection.type == 'vertex' then
				love.graphics.setLine(3, 'rough')
				local radius = 10
				love.graphics.circle('line', selection.vertex[1], selection.vertex[2], radius)
			end

			if selection.type == 'edge' then
				local graph = (selection.edge.side == 'left') and level.leftGraph or level.rightGraph
				local endverts = graph.edges[selection.edge]

				love.graphics.setLine(10, 'rough')
				love.graphics.line(endverts[1][1], endverts[1][2], endverts[2][1], endverts[2][2])
			end
		end

		-- Now the vertices and edges.
		local radius = 5

		love.graphics.setLine(3, 'rough')
		love.graphics.setColor(255, 0, 0, 255)

		for vertex, _ in pairs(level.leftGraph.vertices) do
			love.graphics.circle('fill', vertex[1], vertex[2], radius)

			if vertex.lock then
				local extent = 15
				local halfExtent = extent * 0.5
				love.graphics.rectangle('line', vertex[1] - halfExtent, vertex[2] - halfExtent, extent, extent)
			end
		end

		for edge, endverts in pairs(level.leftGraph.edges) do
			love.graphics.line(endverts[1][1], endverts[1][2], endverts[2][1], endverts[2][2])
		end

		love.graphics.setColor(0, 0, 255, 255)

		for vertex, _ in pairs(level.rightGraph.vertices) do
			love.graphics.circle('fill', vertex[1], vertex[2], radius)

			if vertex.lock then
				local extent = 10
				local halfExtent = extent * 0.5
				love.graphics.rectangle('line', vertex[1] - halfExtent, vertex[2] - halfExtent, extent, extent)
			end
		end

		for edge, endverts in pairs(level.rightGraph.edges) do
			love.graphics.line(endverts[1][1], endverts[1][2], endverts[2][1], endverts[2][2])
		end

		-- Now draw the tags.
		for vertex, _ in pairs(level.leftGraph.vertices) do
			_shadowf(vertex[1], vertex[2], '%s', _tags(vertex))
		end

		for vertex, _ in pairs(level.rightGraph.vertices) do
			_shadowf(vertex[1], vertex[2], '%s', vertex.tag)
		end

		-- If we're in edge mode draw a line to help.
		if state.edge then
			local vertex = state.selection.vertex
			local mx, my = love.mouse.getX(), love.mouse.getY()
			local coord = Vector.new { mx, my }

			love.graphics.line(vertex[1], vertex[2], coord[1], coord[2])
		end

		local numLeft = table.count(level.leftGraph.vertices)
		local numRight = table.count(level.rightGraph.vertices)
		local leftConnect = level.leftGraph:isConnected() and 't' or 'f'
		local rightConnect = level.rightGraph:isConnected() and 't' or 'f'
		_shadowf(10, 10, '#%d left:%d right:%d conn:%s %s',
			state.index,
			numLeft,
			numRight,
			leftConnect,
			rightConnect)
	else
		if not state.graph then
			local rules = {}
			local nextRuleId = 1

			for _, level in ipairs(state.stack) do
				local pattern = level.leftGraph
				local substitute = level.rightGraph
				local map = level.map
				local status, result = pcall(
					function ()
						return GraphGrammar.Rule.new(pattern, substitute, map)
					end)

				if status then
					local name = string.format("rule%d", nextRuleId)
					printf('RULE %s!', name)
					nextRuleId = nextRuleId + 1
					rules[name] = result
				else
					print('RULE FAIL')
				end
				
				print(status, result)
			end

			print('RULEZ', #state.stack, table.count(rules))

			-- TODO: need someway of setting drawYield and replaceYield to
			--       false. Maybe shift+space.

			local grammar = GraphGrammar.new {
				rules = rules,

				springStrength = 1,
				edgeLength = 100,
				repulsion = 500,
				maxDelta = 0.5,
				convergenceDistance = 4,
				drawYield = true,
				replaceYield = true,
			}

			state.coro = coroutine.create(
				function ()
					-- TODO: these should be specified by the rule set.
					local maxIterations = 20
					local minVertices = 10
					local maxVertices = 20
					grammar:build(maxIterations, minVertices, maxVertices)
				end)
		end

		if state.coro then
			if tabbed then
				gProgress = true
			end

			local status, result, forces = coroutine.resume(state.coro)

			if not status then
				error(result)
			end

			if result == nil then
				state.coro = nil
			else
				state.graph = result
			end
		end

		local aabb = AABB.new { xmin = 0, xmax = 0, ymin = 0, ymax = 0 }
		if not state.graph:isEmpty() then
			aabb = graph2D.aabb(state.graph)
		end
		-- In case of zero area AABB.
		aabb = aabb:shrink(-10)
		aabb:similarise(screen)

		love.graphics.setColor(0, 255, 0, 255)
		love.graphics.setLine(3, 'rough')
		local radius = 5

		for vertex, _ in pairs(state.graph.vertices) do
			local pos = aabb:lerpTo(vertex, screen)
			love.graphics.circle('fill', pos[1], pos[2], radius)
		end

		for edge, endverts in pairs(state.graph.edges) do
			local pos1 = aabb:lerpTo(endverts[1], screen)
			local pos2 = aabb:lerpTo(endverts[2], screen)
			love.graphics.line(pos1[1], pos1[2], pos2[1], pos2[2])
		end

		for vertex, _ in pairs(state.graph.vertices) do
			local pos = aabb:lerpTo(vertex, screen)
			_shadowf(pos[1], pos[2], '%s', vertex.tag)
		end
	end
end

function graphmode.mousepressed( x, y, button )
	if button ~= 'l' then
		return
	end

	-- This stops vertices being placed too close to other vertices.
	if state.selection and state.selection.vertex then
		return
	end

	local coord = { x, y }
	local w, h = love.graphics.getWidth(), love.graphics.getHeight()
	local hw = w * 0.5

	local level = state.stack[state.index]

	-- If we're adding a vertex to the left graph we need to add a
	-- corresponding to the right graph.
	if state.leftPane:contains(coord) then
		print('left pane')
		local leftVertex = {
			x,
			y,
			side = 'left',
			tags = { a = true },
			lock = false,
		}

		local rightVertex = {
			x + hw,
			y,
			side = 'right',
			mapped = true,
			tag = 'a',
			lock = false,
		}

		level.leftGraph:addVertex(leftVertex)
		level.rightGraph:addVertex(rightVertex)

		level.map[leftVertex] = rightVertex
	elseif state.rightPane:contains(coord) then
		print('right pane')
		local rightVertex = {
			x,
			y,
			side = 'right',
			mapped = false,
			tag = 'a',
			lock = false,
		}
		level.rightGraph:addVertex(rightVertex)
	end
end

function graphmode.mousereleased( x, y, button )
end

function graphmode.keypressed( key )
	key = key:lower()
	
	if key == 'lshift' or key == 'rshift' then
		if state.selection and state.selection.type == 'vertex' then
			state.edge = true
		end
	elseif key == 'backspace' then
		if state.selection then
			local selection = state.selection
			local level = state.stack[state.index]

			if selection.type == 'vertex' then
				local vertex = selection.vertex
				
				if vertex.side == 'left' then
					level.leftGraph:removeVertex(vertex)
					level.rightGraph:removeVertex(level.map[vertex])
					level.map[vertex] = nil
				elseif not vertex.mapped then
					level.rightGraph:removeVertex(vertex)
				end
			else
				local edge = selection.edge
				local graph = (edge.side == 'left') and level.leftGraph or level.rightGraph

				graph:removeEdge(edge)
			end
		end
	elseif key:find('^([a-z])$') then
		print('taggy', key)
		if state.selection and state.selection.type == 'vertex' then
			local vertex = state.selection.vertex

			if vertex.side == 'right' then
				vertex.tag = key
			else
				local append = love.keyboard.isDown('lshift', 'rshift')

				print('left side', append)

				if append then
					vertex.tags[key] = true
				else
					vertex.tags = { [key] = true }
					local level = state.stack[state.index]
					level.map[vertex].tag = key
				end

				table.print(vertex.tags)
			end
		end
	elseif key == 'up' then
		if state.index > 1 then
			state.index = state.index - 1
		end
	elseif key == 'down' then
		local level = state.stack[state.index]

		-- No point having loads of empty rules.
		if not level.leftGraph:isEmpty() and not level.rightGraph:isEmpty() then
			state.index = state.index + 1

			if not state.stack[state.index] then
				state.stack[state.index] = {
					leftGraph = Graph.new(),
					rightGraph = Graph.new(),
					map = {},
				}
			end
		end
	elseif key == 'f5' then
		local code = _save(state)

		-- print(code)

		local file = love.filesystem.newFile("rules.txt")
		file:open('w')
		file:write(code)
		file:close()
	elseif key == 'f8' then
		local file = love.filesystem.newFile("rules.txt")
		if file:open('r') then
			local code = file:read()
			file:close()

			local data = loadstring(code)()

			-- table.print(data)

			state.stack = _load(data)
			state.index = 1
			state.edge = false
		end
	elseif key == ' ' then
		state.show = not state.show
		state.graph = nil
	elseif key == '=' then
		local selection = state.selection
		if selection and selection.type == 'vertex' and selection.vertex.side == 'left' then
			print('locked!')
			selection.vertex.lock = not selection.vertex.lock
		end
	elseif key == 'return' then
		gProgress = true
	elseif key == 'tab' then
		tabbed = not tabbed
	end
end

function graphmode.keyreleased( key )
	if key == 'lshift' or key == 'rshift' then
		state.edge = false
	end
end