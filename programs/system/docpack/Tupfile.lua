if tup.getconfig("NO_FASM") ~= "" then return end

lang = (tup.getconfig("LANG") == "") and "en_US" or tup.getconfig("LANG")
deps = (lang == "ru_RU") and tup.rule("../../../kernel/trunk/docs/sysfuncr.txt", "iconv -f utf-8 -t cp866 %f > %o", "SysFuncr.txt") or {}
tup.rule({"docpack.asm", extra_inputs = deps}, "fasm -dlang=" .. lang .. " %f %o " .. tup.getconfig("KPACK_CMD"), "docpack")
