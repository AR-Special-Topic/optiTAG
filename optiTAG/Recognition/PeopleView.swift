import SwiftUI
import PhotosUI

struct PeopleView: View {
    @State private var people: [Person] = []
    @State private var error: String?
    var body: some View {
        List {
            if let error { Text(error).foregroundStyle(.red) }
            if people.isEmpty { Text("請在首頁選取照片新增人物") }
            ForEach(people) { person in
                NavigationLink { PersonEditor(person: person) } label: {
                    VStack(alignment: .leading) { Text(person.name); Text(person.tag).font(.caption).foregroundStyle(.secondary) }
                }
            }.onDelete { indices in
                do { for index in indices { try OptiTagDatabase.shared.deletePerson(id: people[index].id) }; reload() }
                catch { self.error = error.localizedDescription }
            }
        }.navigationTitle("人物資料庫").onAppear(perform: reload)
    }
    private func reload() {
        do { people = try OptiTagDatabase.shared.fetchPersons() } catch { self.error = error.localizedDescription }
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
