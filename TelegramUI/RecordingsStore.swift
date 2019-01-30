//
//  RecordersDatabase.swift
//  TelegramUI
//
//  Created by Daniyar Salakhutdinov on 29/01/2019.
//  Copyright © 2019 Telegram. All rights reserved.
//

import UIKit
import RealmSwift
import SwiftSignalKit

import TelegramUIPrivateModule

public class Database {
    
    static let shared: Database = {
        let version = RealmProvider.version
        let migration = RealmProvider.migration
        return Database(version: version, migration: migration)
    }()
    
    struct Sorting {
        let keyPath: String
        let ascending: Bool
    }
    
    private let configuration: Realm.Configuration
    
    var isInWriteTransaction: Bool {
        let realm = try! Realm(configuration: configuration)
        return realm.isInWriteTransaction
    }
    
    init(version: UInt64, migration: @escaping MigrationBlock) {
        self.configuration = Realm.Configuration(schemaVersion: version, migrationBlock: migration)
    }
    
    func add(_ objects: [Object]) {
        let realm = try! Realm(configuration: configuration)
        try! realm.write {
            realm.add(objects)
        }
    }
    
    func getObjects<O: Object>(_ type: O.Type, sorting: Sorting? = nil, filter: NSPredicate? = nil) -> [O] {
        let realm = try! Realm(configuration: configuration)
        var objects = realm.objects(type)
        if let filter = filter {
            objects = objects.filter(filter)
        }
        if let sorting = sorting {
            objects = objects.sorted(byKeyPath: sorting.keyPath, ascending: sorting.ascending)
        }
        return Array(objects)
    }
    
    func remove(_ objects: [Object]) {
        let realm = try! Realm(configuration: configuration)
        try! realm.write {
            realm.delete(objects)
        }
    }
    
    func removeAll<O: Object>(_ type: O.Type) {
        let objects = getObjects(type, sorting: nil, filter: nil)
        remove(objects)
    }
    
    func beginWrite() {
        let realm = try! Realm(configuration: configuration)
        realm.beginWrite()
    }
    
    func commit() {
        let realm = try! Realm(configuration: configuration)
        try! realm.commitWrite()
        realm.refresh()
    }
}

// MARK: - entity

class RecordingEntity: Object {
    @objc dynamic var callId: Int64 = 0
    @objc dynamic var filename: String = ""
}

extension RecordingEntity {
    static func callIdEquals(_ callId: Int64) -> NSPredicate {
        let field = #keyPath(RecordingEntity.callId)
        return NSPredicate(format: "\(field) == \(callId)")
    }
}

// MARK: - recorders database

public protocol RecordersStoreProtocol {
    
    func recordingUrlForCall(withId callId: Int64) -> URL?
    func hasRecordingForCall(withId callId: Int64) -> Bool
    func removeAll()
}

public class RecordingsStore: NSObject, RecordersStoreProtocol, RecorderDelegate {
    
    static public let shared: RecordingsStore = {
        let store = RecordingsStore(database: .shared)
        Recorder.sharedInstance().delegate = store
        return store
    }()
    
    private let database: Database
    private let recordingsPromise = Promise<Int64?>(nil)
    public var recordings: Signal<Int64?, NoError> {
        return self.recordingsPromise.get()
    }
    
    init(database: Database) {
        self.database = database
    }
    
    public func recordingUrlForCall(withId callId: Int64) -> URL? {
        let filter = RecordingEntity.callIdEquals(callId)
        guard let entity = database.getObjects(RecordingEntity.self, filter: filter).first else { return nil }
        let path = FileManager.recordingsFolderUrlPath().appending("/\(entity.filename)")
        let manager = FileManager.default
        guard manager.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
    
    public func hasRecordingForCall(withId callId: Int64) -> Bool {
        return recordingUrlForCall(withId: callId) != nil
    }
    
    public func removeAll() {
        database.removeAll(RecordingEntity.self)
        
        let fileManager = FileManager.default
        let folderPath = FileManager.recordingsFolderUrlPath()
        guard let paths = try? fileManager.contentsOfDirectory(atPath: folderPath) else { return }
        for path in paths {
            try? fileManager.removeItem(atPath: path)
        }
    }
    
    // MARK: recorder delegate
    public func recorder(_ recorder: RecorderProtocol,
                         didFinishRecordingCallWithId callId: Int64,
                         withAudioFileNamed name: String) {
        let entity = RecordingEntity()
        entity.callId = callId
        entity.filename = name
        database.add([entity])
        
        recordingsPromise.set(.single(callId))
    }
}

