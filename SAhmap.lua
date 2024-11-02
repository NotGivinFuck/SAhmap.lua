local module = {
	load = function(filePath, noBuffer)
		local ffi = require("ffi")

		local libs = {
			Windows = "msvcrt",
			Linux = "libc.so.6"
		}
		local libc = ffi.load(libs[ffi.os]) or error(ffi.os .. " is unsupported")

		ffi.cdef[[
			typedef struct FILE FILE;

			FILE* fopen(const char* filename, const char* mode);
			size_t fread(void* ptr, size_t size, size_t count, FILE* stream);
			size_t fwrite(const void* ptr, size_t size, size_t count, FILE* stream);
			int fseek(FILE* stream, long offset, int whence);
			long ftell(FILE* stream);
			int fclose(FILE* stream);
			
			int GetLastError();
		]]

		local file = libc.fopen(filePath, noBuffer and 'r+b' or 'rb')
		if not file then
			return error("Error while opening file: " .. ffi.C.GetLastError())
		end

		libc.fseek(file, 0, 2)
		local fileSize = libc.ftell(file)
		libc.fseek(file, 0, 0)

		local totalPoints = fileSize / 2
		local scale = 6000 / math.sqrt(totalPoints)

		if 6000 % scale ~= 0 then
			return error("Invalid file size")
		end

		local pointData
		local gridSize = 6000 / scale

		if noBuffer then
			file = ffi.gc(file, libc.fclose)
		else
			pointData = ffi.new('int16_t[?]', totalPoints)
			libc.fread(pointData, 2, totalPoints, file)
			libc.fclose(file)
		end

		local function assertValue(v)
			if type(v) == 'table' then
				if #v == 2 and type(v[1]) == "number" and type(v[2]) == "number" then
					return v[1], v[2]
				elseif v.x and v.y and type(v.x) == "number" and type(v.y) == "number" then
					return v.x, v.y
				end
			end
			error("Expected a table with either {float AXIS_X, float AXIS_Y} or {x = float AXIS_X, y = float AXIS_Y}")
		end

		local function getOffset(x, y)
			local gridX = math.floor(x) + 3000
			local gridY = math.abs(math.floor(y) - 3000)
			local iDataPos = (math.floor(gridY / scale) * gridSize) + math.floor(gridX / scale)
			return iDataPos
		end

		local mt = {
			__index = function(self, v)
				local x, y = assertValue(v)
				if x >= -3000 and x <= 3000 and y >= -3000 and y <= 3000 then
					local iDataPos = getOffset(x, y)
					if noBuffer then
						libc.fseek(file, iDataPos * 2, 0)
						local buffer = ffi.new("uint16_t[1]")
						libc.fread(buffer, 2, 1, file)
						return buffer[0] / 100
					end
					return pointData[iDataPos] / 100
				end
				return 0
			end,
			__newindex = function(self, v, newHeight)
				local x, y = assertValue(v)
				if x >= -3000 and x <= 3000 and y >= -3000 and y <= 3000 then
					local iDataPos = getOffset(x, y)
					local heightValue = math.floor(newHeight * 100)

					if noBuffer then
						libc.fseek(file, iDataPos * 2, 0)
						local buffer = ffi.new("uint16_t[1]", heightValue)
						libc.fwrite(buffer, 2, 1, file)
					else
						pointData[iDataPos] = heightValue
					end
				end
			end
		}

		return setmetatable({}, mt)
	end
}

return module
