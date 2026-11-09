//
//  Untitled.swift
//  PHP Monitor
//
//  Created by Nico Verbruggen on 25/08/2025.
//  Copyright © 2025 Nico Verbruggen. All rights reserved.
//

import Foundation

class Packagist {
    static func getLatestStableVersion(
        packageName: String,
        container: Container
    ) async throws -> VersionNumber {
        guard let encodedName = packageName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://repo.packagist.org/p2/\(encodedName).json") else {
            throw PackagistError.invalidURL
        }

        do {
            let response = try await container.webApi.get(
                url, withHeaders: ["User-Agent": "phpmon/\(App.shortVersion)"], withTimeout: .seconds(30)
            )
            guard response.statusCode == 200, let data = response.data else {
                throw PackagistError.networkError(NSError(domain: "", code: response.statusCode, userInfo: nil))
            }

            let decodedResponse = try JSONDecoder()
                .decode(PackagistP2Response.self, from: data)

            guard let versionsArray = decodedResponse.packages[packageName] else {
                throw PackagistError.unexpectedResponseStructure
            }

            // Packagist v2 API returns versions in descending order (newest first).
            // Filter for stable versions - those without a hyphen in version_normalized.
            let stableVersions = versionsArray.filter { version in
                guard let versionNormalized = version.version_normalized else {
                    return false
                }
                // Filter out pre-release versions (alpha, beta, RC, etc.)
                return !versionNormalized.contains("-")
            }

            // Get the first stable version (which is the latest)
            guard let latestVersionInfo = stableVersions.first,
                  let latestVersion = latestVersionInfo.version else {
                throw PackagistError.noStableVersions
            }

            return try VersionNumber.parse(latestVersion)
        } catch {
            // Catch any errors that occurred and re-throw them as our custom error type for better diagnostics.
            if let decodingError = error as? DecodingError {
                throw PackagistError.jsonDecodingError(decodingError)
            } else if let urlError = error as? URLError {
                throw PackagistError.networkError(urlError)
            } else {
                throw error
            }
        }
    }
}
