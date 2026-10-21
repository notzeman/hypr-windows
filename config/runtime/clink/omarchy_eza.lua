-- Loaded by the existing Clink installation in interactive CMD sessions.
-- Keep CMD's built-in dir command and all other aliases unchanged.
local executable = os.getenv("LOCALAPPDATA") .. "\\Programs\\eza\\eza.exe"
local function register_listing_alias()
    os.setalias("l", '"' .. executable .. '" --long --all --header --color=auto --icons=auto $*')
    os.setalias("clear", "cls")
    os.setalias("pwd", "echo %cd%")
end
clink.onbeginedit(register_listing_alias)
