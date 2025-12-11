//
//  ContactListView.swift
//  AppleiChat
//
//  Created by Dennis Stewart Jr. on 10/3/25.
//

import SwiftUI

struct ContactListView: View {
    let contacts: [Contact]

    var body: some View {
        NavigationView {
            List(contacts) { contact in
                ContactRow(contact: contact)
            }
            .navigationTitle("Contacts")
        }
    }
}

#Preview {
    ContactListView(contacts: Contact.sampleData)
}
