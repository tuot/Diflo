//
//  Item.swift
//  DiffZen
//
//  Created by Levi on 2026/8/18.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
