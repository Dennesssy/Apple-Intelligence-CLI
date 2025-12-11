//
//  ContentView.swift
//  AppleiChat
//
//  Created by Dennis Stewart Jr. on 10/3/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ContactListView(contacts: Contact.sampleData)
    }
}

#Preview {
    ContentView()
}
