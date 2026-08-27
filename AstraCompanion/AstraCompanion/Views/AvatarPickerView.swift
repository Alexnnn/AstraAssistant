//
//  AvatarPickerView.swift
//  AstraCompanion
//
//  Created by Alex on 23/8/26.
//


import SwiftUI
import PhotosUI
import UIKit

struct AvatarPickerView: View {
    let title: String
    let onImageSelected: (Data) -> Void
    let onCancel: () -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var selectedData: Data?
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                preview
                    .padding(.top, 24)

                if isLoading {
                    ProgressView("Loading photo...")
                        .padding(.vertical, 4)
                }

                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                PhotosPicker(
                    selection: $selectedItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label(selectedImage == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading)
                .onChange(of: selectedItem) { _, newItem in
                    Task {
                        await loadImage(from: newItem)
                    }
                }

                Button {
                    guard let selectedData else { return }
                    onImageSelected(selectedData)
                } label: {
                    Label("Save Avatar", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(selectedData == nil || isLoading)

                Spacer()
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.12))
                .frame(width: 210, height: 210)

            if let selectedImage {
                Image(uiImage: selectedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 210, height: 210)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.gray.opacity(0.25), lineWidth: 2)
                    )
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 92))
                    .foregroundStyle(.gray.opacity(0.45))
            }
        }
        .frame(width: 210, height: 210)
    }

    private func loadImage(from item: PhotosPickerItem?) async {
        guard let item else { return }

        await MainActor.run {
            isLoading = true
            errorText = nil
        }

        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                await MainActor.run {
                    errorText = "Failed to load selected image."
                }
                return
            }

            await MainActor.run {
                selectedData = data
                selectedImage = image
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }
}
