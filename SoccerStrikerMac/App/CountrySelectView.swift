import SwiftUI

/// 国（代表チーム）選択画面。
/// YOU と CPU の 2 枠を横並びにし、それぞれの「台（スタンド）」の上に
/// 選んだ国の選手モデルが立つ。下の国旗グリッドで自国/相手を選ぶ。
struct CountrySelectView: View {
    let onStart: (_ home: Country, _ away: Country) -> Void
    let onBack: () -> Void

    @State private var home: Country = .japan
    @State private var away: Country = .brazil
    @State private var editing: Slot = .home

    enum Slot { case home, away }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.10, blue: 0.06), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                header
                matchup
                flagGrid
                startButton
            }
            .padding(24)
            .frame(maxWidth: 820)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("SELECT MATCH")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.title3.bold())
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    // MARK: - Matchup（YOU と CPU の台 + 選手）

    private var matchup: some View {
        HStack(alignment: .bottom, spacing: 20) {
            podium(.home, home, label: "YOU")
            VStack(spacing: 6) {
                Text("VS").font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxHeight: .infinity)
            podium(.away, away, label: "CPU")
        }
        .frame(height: 360)
    }

    private func podium(_ slot: Slot, _ country: Country, label: String) -> some View {
        let active = editing == slot
        return Button { editing = slot } label: {
            VStack(spacing: 0) {
                // 選手モデル（台の上に立つ）
                playerStage(country)
                // 台（スタンド）
                standCard(country, label: label, active: active)
            }
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(active ? Color.yellow : .clear, lineWidth: 3)
        )
    }

    /// 台の上に立つ選手モデル画像（無ければ国旗プレースホルダ）。
    private func playerStage(_ country: Country) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white.opacity(0.04))

            if let img = country.playerImage {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxHeight: 290)
            } else {
                VStack(spacing: 12) {
                    FlagView(country: country, height: 80)
                    Text("Player model coming soon")
                        .font(.caption2).foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    /// 選手が乗る台。国旗・国名・YOU/CPU を表示。
    private func standCard(_ country: Country, label: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            FlagView(country: country, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption2.bold())
                    .foregroundStyle(active ? .yellow : .white.opacity(0.6))
                Text(country.name).font(.headline.bold()).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(
            LinearGradient(colors: [country.primaryColor.opacity(0.85), country.primaryColor.opacity(0.5)],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 6)
    }

    // MARK: - Flag grid

    private var flagGrid: some View {
        HStack(spacing: 10) {
            ForEach(Country.all) { c in
                Button { pick(c) } label: {
                    VStack(spacing: 6) {
                        FlagView(country: c, height: 34)
                        Text(c.name).font(.caption2).foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(c.primaryColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected(c) ? c.primaryColor : .white.opacity(0.1), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func isSelected(_ c: Country) -> Bool {
        (editing == .home ? home : away).id == c.id
    }

    private func pick(_ c: Country) {
        if editing == .home {
            home = c
            if away.id == c.id { away = Country.all.first { $0.id != c.id } ?? away }
            editing = .away
        } else {
            away = c
            if home.id == c.id { home = Country.all.first { $0.id != c.id } ?? home }
        }
    }

    // MARK: - Start

    private var startButton: some View {
        Button { onStart(home, away) } label: {
            Text("START MATCH")
                .font(.title2.bold())
                .padding(.horizontal, 56).padding(.vertical, 14)
                .background(Color.green, in: Capsule())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .disabled(home.id == away.id)
        .opacity(home.id == away.id ? 0.5 : 1)
    }
}
