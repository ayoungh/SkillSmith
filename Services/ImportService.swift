import Foundation

struct ImportService {
    func importSkill(_ skill: SkillRecord) -> SkillRecord {
        var updated = skill
        if updated.managementState == .externalImportable {
            updated.managementState = .importedExternal
            updated.source.origin = .importedInstall
        }
        return updated
    }

    func attachLibrarySource(_ source: SkillSource, to skill: SkillRecord) -> SkillRecord {
        var updated = skill
        updated.source = source
        updated.managementState = .managedLocal
        updated.installMode = .symlink
        return updated
    }
}
