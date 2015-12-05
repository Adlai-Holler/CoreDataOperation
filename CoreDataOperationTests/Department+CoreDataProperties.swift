//
//  Department+CoreDataProperties.swift
//  CoreDataUpdateOperation
//
//  Created by Adlai Holler on 12/4/15.
//  Copyright © 2015 Adlai Holler. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Department {

    @NSManaged var name: String
    @NSManaged var employees: Set<Employee>

}
