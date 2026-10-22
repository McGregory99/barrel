import BarrelCore
import Foundation

public enum RecipeParser {
    public static let supportedFormatVersion = 1

    public static func parse(_ data: Data) throws -> Recipe {
        let root: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw RecipeError.invalidJSON("top level must be an object")
            }
            root = object
        } catch let error as RecipeError {
            throw error
        } catch {
            throw RecipeError.invalidJSON(error.localizedDescription)
        }

        guard let version = root["formatVersion"] else { throw RecipeError.missingField("formatVersion") }
        guard let versionNumber = version as? Int else {
            throw RecipeError.invalidValue(field: "formatVersion", reason: "must be an integer")
        }
        guard versionNumber == supportedFormatVersion else {
            throw RecipeError.unsupportedFormatVersion(versionNumber)
        }

        let id = try string(root, "id", required: true)!
        guard isValidID(id) else {
            throw RecipeError.invalidValue(field: "id", reason: "use lowercase letters, digits, '.', '-' and '_'")
        }
        let name = try string(root, "name", required: true)!
        let description = try string(root, "description", required: false)

        let bottle = try parseBottle(root["bottle"])
        let dependencies = try stringArray(root["dependencies"], field: "dependencies")
        let steps = try parseSteps(root["steps"])
        var hidden = false
        if let value = root["hidden"] {
            guard let flag = value as? Bool, CFGetTypeID(value as CFTypeRef) == CFBooleanGetTypeID() else {
                throw RecipeError.invalidValue(field: "hidden", reason: "must be true or false")
            }
            hidden = flag
        }
        return Recipe(id: id, name: name, description: description, bottle: bottle,
                      dependencies: dependencies, steps: steps, hidden: hidden)
    }

    static func isValidID(_ id: String) -> Bool {
        func lower(_ c: Unicode.Scalar) -> Bool { ("a"..."z").contains(c) || ("0"..."9").contains(c) }
        guard let first = id.unicodeScalars.first, lower(first) else { return false }
        return id.unicodeScalars.allSatisfy { lower($0) || "._-".unicodeScalars.contains($0) }
    }

    private static func parseBottle(_ value: Any?) throws -> BottleSettings {
        guard let value else { return BottleSettings() }
        guard let dict = value as? [String: Any] else {
            throw RecipeError.invalidValue(field: "bottle", reason: "must be an object")
        }
        var settings = BottleSettings()
        if let template = try string(dict, "windowsVersion", required: false, path: "bottle.") {
            do { settings.windowsVersion = try WindowsVersion(template: template) } catch {
                throw RecipeError.invalidValue(field: "bottle.windowsVersion", reason: "\(error)")
            }
        }
        if let backend = try string(dict, "graphicsBackend", required: false, path: "bottle.") {
            do { settings.graphicsBackend = try GraphicsBackend(name: backend) } catch {
                throw RecipeError.invalidValue(field: "bottle.graphicsBackend", reason: "\(error)")
            }
        }
        if let msync = dict["msync"] {
            guard let flag = msync as? Bool else {
                throw RecipeError.invalidValue(field: "bottle.msync", reason: "must be true or false")
            }
            settings.msync = flag
        }
        if let apps = dict["appGraphics"] {
            guard let map = apps as? [String: Any] else {
                throw RecipeError.invalidValue(field: "bottle.appGraphics", reason: "must be an object of executable: backend")
            }
            for (executable, value) in map {
                guard let name = value as? String, let backend = try? GraphicsBackend(name: name) else {
                    throw RecipeError.invalidValue(field: "bottle.appGraphics.\(executable)",
                                                   reason: "must be one of wined3d, dxvk, dxmt")
                }
                settings.appGraphics[executable] = backend
            }
        }
        return settings
    }

    private static func parseSteps(_ value: Any?) throws -> [Step] {
        guard let value else { return [] }
        guard let array = value as? [[String: Any]] else {
            throw RecipeError.invalidValue(field: "steps", reason: "must be an array of objects")
        }
        var steps: [Step] = []
        var downloads: Set<String> = []
        for (offset, dict) in array.enumerated() {
            let index = offset + 1
            let path = "steps[\(index)]."
            guard let kind = try string(dict, "kind", required: true, path: path) else { continue }
            switch kind {
            case "download":
                let step = try parseDownload(dict, index: index, path: path)
                downloads.insert(step.fileName)
                steps.append(.download(step))
            case "run":
                let step = try parseRun(dict, path: path)
                if let file = step.file, !downloads.contains(file) {
                    throw RecipeError.unknownDownloadReference(file: file, step: index)
                }
                steps.append(.run(step))
            case "registry":
                steps.append(.registry(try parseRegistry(dict, path: path)))
            case "dllOverride":
                steps.append(.dllOverride(try parseOverride(dict, path: path)))
            default:
                throw RecipeError.unknownStepKind(kind: kind, step: index)
            }
        }
        return steps
    }

    private static func parseDownload(_ dict: [String: Any], index: Int, path: String) throws -> DownloadStep {
        let urlText = try string(dict, "url", required: true, path: path)!
        guard let url = URL(string: urlText), url.scheme == "https" || url.scheme == "http" else {
            throw RecipeError.invalidValue(field: path + "url", reason: "must be an http(s) URL")
        }
        guard let sha = try string(dict, "sha256", required: false, path: path), !sha.isEmpty else {
            throw RecipeError.missingSHA256(step: index)
        }
        let hash = sha.lowercased()
        guard hash.count == 64, hash.allSatisfy(\.isHexDigit) else {
            throw RecipeError.invalidSHA256(step: index, value: sha)
        }
        let fileName = try string(dict, "fileName", required: true, path: path)!
        try validateFileName(fileName, field: path + "fileName")
        return DownloadStep(url: url, sha256: hash, fileName: fileName)
    }

    private static func parseRun(_ dict: [String: Any], path: String) throws -> RunStep {
        let file = try string(dict, "file", required: false, path: path)
        let target = try string(dict, "path", required: false, path: path)
        guard (file == nil) != (target == nil) else {
            throw RecipeError.invalidValue(field: path + "file", reason: "give exactly one of 'file' or 'path'")
        }
        if let file { try validateFileName(file, field: path + "file") }
        let arguments = try stringArray(dict["arguments"], field: path + "arguments")
        var codes: [Int32] = [0]
        if let raw = dict["expectedExitCodes"] {
            guard let list = raw as? [Int], !list.isEmpty else {
                throw RecipeError.invalidValue(field: path + "expectedExitCodes", reason: "must be a non-empty array of integers")
            }
            codes = list.map(Int32.init)
        }
        return RunStep(file: file, path: target, arguments: arguments, expectedExitCodes: codes)
    }

    private static func parseRegistry(_ dict: [String: Any], path: String) throws -> RegistryStep {
        let key = try string(dict, "key", required: true, path: path)!
        let roots = ["HKCU", "HKLM", "HKCR", "HKU", "HKEY_CURRENT_USER", "HKEY_LOCAL_MACHINE"]
        guard roots.contains(where: { key == $0 || key.hasPrefix($0 + "\\") }) else {
            throw RecipeError.invalidValue(field: path + "key", reason: "must start with a registry root such as HKCU\\ or HKLM\\")
        }
        let name = try string(dict, "name", required: true, path: path)!
        let typeName = try string(dict, "type", required: false, path: path) ?? "REG_SZ"
        guard let type = RegistryType(rawValue: typeName) else {
            throw RecipeError.invalidValue(field: path + "type", reason: "must be REG_SZ or REG_DWORD")
        }
        let data: String
        switch dict["data"] {
        case let text as String: data = text
        case let number as Int: data = String(number)
        case nil: throw RecipeError.missingField(path + "data")
        default: throw RecipeError.invalidValue(field: path + "data", reason: "must be a string or integer")
        }
        if type == .dword, UInt32(data) == nil {
            throw RecipeError.invalidValue(field: path + "data", reason: "REG_DWORD needs an unsigned 32-bit integer")
        }
        return RegistryStep(key: key, name: name, type: type, data: data)
    }

    private static func parseOverride(_ dict: [String: Any], path: String) throws -> DLLOverrideStep {
        let dll = try string(dict, "dll", required: true, path: path)!
        let modeName = try string(dict, "mode", required: true, path: path)!
        guard let mode = DLLOverrideMode(rawValue: modeName) else {
            throw RecipeError.invalidValue(
                field: path + "mode",
                reason: "must be one of " + DLLOverrideMode.allCases.map(\.rawValue).joined(separator: ", "))
        }
        guard !dll.isEmpty, !dll.contains("\\"), !dll.contains("/"), !dll.contains(" ") else {
            throw RecipeError.invalidValue(field: path + "dll", reason: "use a bare DLL name such as 'd3dcompiler_47'")
        }
        return DLLOverrideStep(dll: dll, mode: mode)
    }

    private static func validateFileName(_ name: String, field: String) throws {
        guard !name.isEmpty, !name.contains("/"), !name.contains("\\"), !name.hasPrefix("."), name != ".." else {
            throw RecipeError.invalidValue(field: field, reason: "must be a plain file name")
        }
    }

    private static func string(_ dict: [String: Any], _ key: String, required: Bool, path: String = "") throws -> String? {
        guard let value = dict[key] else {
            if required { throw RecipeError.missingField(path + key) }
            return nil
        }
        guard let text = value as? String else {
            throw RecipeError.invalidValue(field: path + key, reason: "must be a string")
        }
        return text
    }

    private static func stringArray(_ value: Any?, field: String) throws -> [String] {
        guard let value else { return [] }
        guard let array = value as? [String] else {
            throw RecipeError.invalidValue(field: field, reason: "must be an array of strings")
        }
        return array
    }
}
