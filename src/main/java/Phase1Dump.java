import jdbm.RecordManager;
import jdbm.RecordManagerFactory;
import jdbm.helper.FastIterator;
import jdbm.htree.HTree;

import java.io.BufferedWriter;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class Phase1Dump {
    private final RecordManager recman;
    private final HTree idToUrl;
    private final HTree pageMeta;
    private final HTree parentToChildren;

    private Phase1Dump(String dbBasePath) throws IOException {
        recman = RecordManagerFactory.createRecordManager(dbBasePath);
        idToUrl = openHTree("idToUrl");
        pageMeta = openHTree("pageMeta");
        parentToChildren = openHTree("parentToChildren");
    }

    private HTree openHTree(String name) throws IOException {
        long recid = recman.getNamedObject(name);
        if (recid == 0) {
            throw new IOException("Missing table in DB: " + name);
        }
        return HTree.load(recman, recid);
    }

    private void close() throws IOException {
        recman.close();
    }

    private static String formatDate(long epochMillis) {
        SimpleDateFormat sdf = new SimpleDateFormat("EEE, dd MMM yyyy HH:mm:ss z", Locale.ENGLISH);
        return sdf.format(new Date(epochMillis));
    }

    private static List<Map.Entry<String, Integer>> topKeywords(Map<String, Integer> freqMap, int limit) {
        ArrayList<Map.Entry<String, Integer>> entries = new ArrayList<Map.Entry<String, Integer>>(freqMap.entrySet());
        Collections.sort(entries, new Comparator<Map.Entry<String, Integer>>() {
            @Override
            public int compare(Map.Entry<String, Integer> a, Map.Entry<String, Integer> b) {
                int freqDiff = b.getValue().intValue() - a.getValue().intValue();
                if (freqDiff != 0) {
                    return freqDiff;
                }
                return a.getKey().compareTo(b.getKey());
            }
        });
        if (entries.size() > limit) {
            return entries.subList(0, limit);
        }
        return entries;
    }

    @SuppressWarnings("unchecked")
    private void dumpToFile(String outputPath) throws IOException {
        ArrayList<Integer> ids = new ArrayList<Integer>();
        FastIterator iterator = idToUrl.keys();
        Integer key;
        while ((key = (Integer) iterator.next()) != null) {
            ids.add(key);
        }
        Collections.sort(ids);

        BufferedWriter writer = new BufferedWriter(new OutputStreamWriter(new FileOutputStream(outputPath), StandardCharsets.UTF_8));
        try {
            for (int i = 0; i < ids.size(); i++) {
                Integer id = ids.get(i);
                PageInfo info = (PageInfo) pageMeta.get(id);
                if (info == null) {
                    continue;
                }

                writer.write(info.title == null ? "" : info.title);
                writer.newLine();
                writer.write(info.url == null ? "" : info.url);
                writer.newLine();
                writer.write(formatDate(info.lastModified) + ", " + info.size);
                writer.newLine();

                List<Map.Entry<String, Integer>> top = topKeywords(info.bodyFreq, 10);
                StringBuilder keywordLine = new StringBuilder();
                for (int j = 0; j < top.size(); j++) {
                    if (j > 0) {
                        keywordLine.append("; ");
                    }
                    keywordLine.append(top.get(j).getKey()).append(" ").append(top.get(j).getValue());
                }
                writer.write(keywordLine.toString());
                writer.newLine();

                HashSet<Integer> children = (HashSet<Integer>) parentToChildren.get(id);
                if (children != null && !children.isEmpty()) {
                    ArrayList<Integer> childIds = new ArrayList<Integer>(children);
                    Collections.sort(childIds);
                    int count = 0;
                    for (int j = 0; j < childIds.size() && count < 10; j++) {
                        String childUrl = (String) idToUrl.get(childIds.get(j));
                        if (childUrl == null) {
                            continue;
                        }
                        writer.write(childUrl);
                        writer.newLine();
                        count++;
                    }
                }

                writer.write("------------------------------------------------------------");
                writer.newLine();
            }
        } finally {
            writer.flush();
            writer.close();
        }
    }

    public static void main(String[] args) {
        String dbBasePath = "db/phase1";
        String outputPath = "spider result.txt";

        if (args.length >= 1) {
            dbBasePath = args[0];
        }
        if (args.length >= 2) {
            outputPath = args[1];
        }

        Phase1Dump dumper = null;
        try {
            dumper = new Phase1Dump(dbBasePath);
            dumper.dumpToFile(outputPath);
            System.out.println("Dump completed: " + outputPath);
        } catch (Exception ex) {
            System.err.println("Dump failed: " + ex.toString());
            ex.printStackTrace();
        } finally {
            if (dumper != null) {
                try {
                    dumper.close();
                } catch (IOException ignored) {
                }
            }
        }
    }
}
