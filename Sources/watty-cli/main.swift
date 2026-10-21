import Foundation
import WattyCLI

exit(await CommandLineTool.run(arguments: Array(CommandLine.arguments.dropFirst())))
