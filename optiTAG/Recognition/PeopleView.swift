import SwiftUI
import PhotosUI

struct PeopleView: View {
    @ObservedObject var viewModel: MainViewModel
    @State private var showsEnrollment = false
    @State private var deletingPerson: Person?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var enrollmentData: Data?
    @State private var personName = ""
    @State private var personTag = ""
    @FocusState private var inputFocused: Bool
    @State private var people: [Person] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if people.isEmpty { Text("尚未新增人物").foregroundStyle(.secondary) }
            ForEach(people) { person in
                NavigationLink { PersonEditor(person: person) } label: {
                    VStack(alignment: .leading) { Text(person.name); Text(person.tag).font(.caption).foregroundStyle(.secondary) }
                }
                .contextMenu {
                    Button("刪除人物", systemImage: "trash", role: .destructive) {
                        deletingPerson = person
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showsEnrollment = true
            } label: {
                Label("新增人物", systemImage: "person.badge.plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .alert("刪除人物？", isPresented: Binding(
            get: { deletingPerson != nil },
            set: { if !$0 { deletingPerson = nil } }
        ), presenting: deletingPerson) { person in
            Button("取消", role: .cancel) {}
            Button("刪除", role: .destructive) {
                do {
                    try OptiTagDatabase.shared.deletePerson(id: person.id)
                    reload()
                } catch { self.error = error.localizedDescription }
            }
        } message: { person in
            Text("將刪除「\(person.name)」及其登錄特徵。")
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showsEnrollment, onDismiss: resetEnrollment) {
            NavigationStack {
                Form {
                    Section("登錄新人物") {
                        TextField("人物姓名", text: $personName).textFieldStyle(.roundedBorder).focused($inputFocused).submitLabel(.done).onSubmit { inputFocused = false }
                        TextField("標籤（例如朋友、同學）", text: $personTag).textFieldStyle(.roundedBorder).focused($inputFocused).submitLabel(.done).onSubmit { inputFocused = false }
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(enrollmentData == nil ? "選擇單人正面照片" : "已選擇照片，點此更換", systemImage: "photo")
                        }
                        .disabled(viewModel.isEnrolling)
                        if let data = enrollmentData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 120)
                        }
                        Button(viewModel.isEnrolling ? "建立特徵中…" : "新增人物") {
                            inputFocused = false
                            if let data = enrollmentData { viewModel.enroll(data: data, name: personName, tag: personTag) }
                        }
                        .disabled(enrollmentData == nil || personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isEnrolling)
                        Text(viewModel.recognitionStatus).font(.caption)
                    }
                }
                .navigationTitle("新增人物")
                .navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showsEnrollment = false }.disabled(viewModel.isEnrolling)
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("完成") { inputFocused = false }
                    }
                }
            }
            .interactiveDismissDisabled(viewModel.isEnrolling)
        }
        .onChange(of: viewModel.enrollmentRevision) { _, _ in
            reload()
            showsEnrollment = false
        }
        .task(id: selectedPhoto) {
            enrollmentData = nil
            guard let photo = selectedPhoto else { return }
            do { enrollmentData = try await photo.loadTransferable(type: Data.self) }
            catch { viewModel.databaseErrorMessage = "照片讀取失敗：\(error.localizedDescription)" }
        }
    }
    private func resetEnrollment() {
        selectedPhoto = nil
        enrollmentData = nil
        personName = ""
        personTag = ""
    }

    private func reload() {
        do {
            people = try OptiTagDatabase.shared.fetchPersons().sorted {
                $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

private struct PersonEditor: View {
    let person: Person
    @State private var name = ""
    @State private var tag = ""
    @State private var photo: PhotosPickerItem?
    @State private var samples: [OptiTagDatabase.FaceSample] = []
    @State private var message = ""
    @State private var busy = false
    @FocusState private var focused: Bool
    private let worker = RecognitionWorker()
    var body: some View {
        Form {
            Section("人物") {
                TextField("姓名", text: $name).focused($focused)
                TextField("標籤", text: $tag).focused($focused)
                Button("儲存") {
                    focused = false
                    do {
                        try OptiTagDatabase.shared.updatePerson(id: person.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), tag: tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未標記" : tag.trimmingCharacters(in: .whitespacesAndNewlines))
                        message = "已儲存"; reload()
                    } catch { message = error.localizedDescription }
                }.disabled(busy)
            }
            Section("登錄特徵（原始照片不保存）") {
                ForEach(Array(samples.enumerated()), id: \.element.id) { index, _ in Text("登錄照片特徵 \(index + 1)") }
                    .onDelete { indices in
                        do { for index in indices { try OptiTagDatabase.shared.deleteSample(id: samples[index].id) }; reload() }
                        catch { message = error.localizedDescription }
                    }
                PhotosPicker("新增登錄照片", selection: $photo, matching: .images).disabled(busy)
                Text("可刪除個別特徵；沒有特徵時，此人物不參與辨識。").font(.caption)
            }
            if busy { ProgressView() }
            if !message.isEmpty { Text(message) }
        }
        .navigationTitle("編輯人物")
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完成") { focused = false } } }
        .onAppear { name = person.name; tag = person.tag; reload() }
        .task(id: photo) {
            guard let photo else { return }
            busy = true
            do {
                guard let data = try await photo.loadTransferable(type: Data.self) else { throw PersonError.message("無法讀取照片") }
                worker.embedding(from: data) { result in
                    defer { busy = false; self.photo = nil }
                    do { try OptiTagDatabase.shared.addSample(personID: person.id, embedding: result.get()); message = "已新增照片特徵"; reload() }
                    catch { message = error.localizedDescription }
                }
            } catch { message = error.localizedDescription; busy = false; self.photo = nil }
        }
    }
    private func reload() { samples = (try? OptiTagDatabase.shared.fetchFaceSamples().filter { $0.personID == person.id }) ?? [] }
}
