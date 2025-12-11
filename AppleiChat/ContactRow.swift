//
//  ContactRow.swift
//  AppleiChat
//
//  Created by Dennis Stewart Jr. on 10/3/25.
//

import SwiftUI

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack {
            Image(systemName: contact.imageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            Text(contact.name)
                .font(.headline)
            Spacer()
        }
        .padding()
    }
}

#Preview {
    ContactRow(contact: Contact.sampleData[0])
}
